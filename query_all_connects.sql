select b.road_id
from road_connector as a, road_connector as b
where a.road_id = 1
and b.connector_id = a.connector_id
and b.road_id != 1
