--road_line--

DROP TABLE IF EXISTS "road_line" CASCADE; 

CREATE TABLE "road_line" (
    "id" serial NOT NULL PRIMARY KEY,
    "source" integer,
    "target" integer,
    "geom" geometry(LineString,4326)
    );

CREATE INDEX road_line_source_idx
  ON road_line
  ("source");

CREATE INDEX road_line_target_idx
  ON road_line
  ("target");

CREATE INDEX road_line_geom_idx
  ON road_line
  USING gist
  ("geom");

--
