
--road--

DROP TABLE IF EXISTS "road" CASCADE; 

CREATE TABLE "road" (
    "id" serial NOT NULL PRIMARY KEY,
    "target" integer,
    "source" integer,
    "width" integer default 20,
    "geom" geometry(LineString,3857)
    );

CREATE INDEX road_target_idx
  ON road
  (target);

CREATE INDEX road_source_idx
  ON road
  (source);

CREATE INDEX road_geom_idx
  ON road
  USING gist
  (geom);

--road_history--

DROP TABLE IF EXISTS "road_history" CASCADE; 

CREATE TABLE "road_history" (
    "id" serial NOT NULL PRIMARY KEY,
    "query" text,
    "width" integer default 10,
    "geom" geometry(LineString,3857)
    );

CREATE INDEX road_history_geom_idx
  ON road_history
  USING gist
  (geom);

--connector--

DROP TABLE IF EXISTS "connector" CASCADE; 

CREATE TABLE "connector" (
    "id" serial NOT NULL PRIMARY KEY,
    "width" integer,
    "geom" geometry(Polygon,3857)
    );

CREATE INDEX connector_geom_idx
  ON connector
  USING gist
  (geom);

--road_connector--

DROP TABLE IF EXISTS "road_connector" CASCADE; 

CREATE TABLE "road_connector" (
    "id" serial NOT NULL PRIMARY KEY,
    "road_id" integer references road,
    "connector_id" integer references connector
    );

--roating view

DROP VIEW IF EXISTS "roating" CASCADE; 

CREATE VIEW roating AS 
    select road.id,
        ST_Length(road.geom) as lenght,
        array(
            select b.road_id
            from road_connector as a, road_connector as b
            where a.road_id = road.id
            and b.connector_id = a.connector_id
            and b.road_id != road.id
        ) as contacts,
        road.geom as geom
    from road;


--triggers --

create or replace function connector_clean_ops() returns trigger as $connector_clean_ops$
    begin
        if (TG_OP = 'DELETE') then
            delete
            from road_connector
            where connector_id = OLD.id;
            return OLD; 
        end if;
    end;
$connector_clean_ops$ language plpgsql
;

drop trigger if exists connector_clean_ops on road;

create trigger connector_clean_ops
before delete on connector
   for each row execute procedure connector_clean_ops()
;


create or replace function connector_before_ops() returns trigger as $connector_before_ops$
    declare
        ends_array geometry(Point)[];
        line_point geometry(Point);
        line_fix geometry(LineString);
        line_fix_go boolean;
        connector_id integer;
    begin
        -- delete road
        if (TG_OP = 'DELETE') then
            delete
            from road_connector
            where road_id = OLD.id;$connector_before_ops$ language plpgsql

            delete
            from connector
            where id in (
                select connector.id
                from connector
                where (ST_Within(ST_StartPoint(OLD.geom),connector.geom) or ST_Within(ST_EndPoint(OLD.geom),connector.geom))
                and connector.id not in (
                    select road_connector.connector_id
                    from road_connector
                    )
                );

            return OLD;
        end if;
        -- clean old connector from update
--        if (TG_OP = 'INSERT') or (TG_OP = 'UPDATE') then
--        end if;
        -- fix line
        if (TG_OP = 'INSERT') or (TG_OP = 'UPDATE') then
            ends_array = array[ST_StartPoint(NEW.geom),ST_EndPoint(NEW.geom)];
            line_fix = NEW.geom;
            line_fix_go = False;
            foreach line_point in array ends_array
            loop
                connector_id = (
                    select id
                    from connector
                    where ST_Within(line_point,geom)
                );
                if connector_id > 0 then
                    line_fix = (
                        select ST_Snap(
                            line_fix,
                            ST_Centroid(connector.geom),
                            connector.width*2
                        )
                        from connector
                        where connector.id = connector_id
                    );
                    line_fix_go = True;
                end if;
            end loop;
            if line_fix_go then
                NEW.geom = line_fix;
            end if;
            return NEW; 
        end if;
    end;
$connector_before_ops$ language plpgsql
;

drop trigger if exists connector_before_ops on road;

create trigger connector_before_ops
before insert or update or delete on road
   for each row execute procedure connector_before_ops()
;



create or replace function connector_after_ops() returns trigger as $connector_after_ops$
    declare
        ends_array geometry(Point)[];
        line_point geometry(Point);
        connector_id integer;
    begin
        --backup line ops
        if (TG_OP = 'INSERT') or (TG_OP = 'UPDATE') then
            insert into road_history (query,width,geom)
            values (
                TG_OP,
                NEW.width,
                NEW.geom
            );
        elsif (TG_OP = 'DELETE') then
            insert into road_history (query,width,geom)
            values (
                TG_OP,
                OLD.width,
                OLD.geom
            );
        end if;
        -- del line
--        if (TG_OP = 'DELETE') then
--            ends_array = array[ST_StartPoint(OLD.geom),ST_EndPoint(OLD.geom)];
--            foreach line_point in array new_ends_array
--            loop
--            end loop;
--        end if;
        -- add line
        if (TG_OP = 'INSERT') then
            ends_array = array[ST_StartPoint(NEW.geom),ST_EndPoint(NEW.geom)];
            foreach line_point in array ends_array
            loop
                connector_id = (
                    select id
                    from connector
                    where ST_Within(line_point,geom)
                );
                if connector_id > 0 then
                    insert into road_connector (road_id,connector_id)
                    values(
                        NEW.id,
                        connector_id
                    );
                else
                    insert into connector (width,geom)
                    values(
                        NEW.width,
                        ST_Buffer(line_point,NEW.width*2)
                    );
                    
                    insert into road_connector (road_id,connector_id)
                    values(
                        NEW.id,
                        (
                            select id
                            from connector
                            where ST_Centroid(geom) = line_point
                        )
                    );
                end if;
            end loop;
        end if;
        -- update line
--        if (TG_OP = 'UPDATE') then
--        end if;
        return NEW; 
    end;
$connector_after_ops$ language plpgsql
;

drop trigger if exists connector_after_ops on road;

create trigger connector_after_ops
after insert or update or delete on road
   for each row execute procedure connector_after_ops()
;


--delete road trigger --
  
