insert into road_line (geom)
select st_snap(a.geom, b.geom, ST_Distance(a.geom,b.geom)*1.01)
from road_line as a, road_line as b
where a.id =2
and b.id =3
