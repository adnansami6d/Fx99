layout.json = the built-in map, as data. Change it, the map changes (no code needed).
 ground  : size in meters (400 = 400 m x 400 m). North = hill, west / east / south = sea (scripts/coast.gd)
 roads   : x, z = center, w = width (x side), d = length (z side). Long in z = north-south road, long in x = east-west road
 plots   : fields. x, z = center, w, d = size, cell = grid cell size in meters.
           Each plot gets soil (dry -> dark when plowed). No fences.
           "fence": false = no fence.
 objects : type (house, house2, house3, barn, silo, shed, well, greenhouse, tree, or your own scene res://props/<type>.tscn),
           x, z, rot (degrees; 0 = the door looks to +z, 90 = east, 180 = north, 270 = west)
 ponds   : x, z, r (radius). Water blocks the way.
 forests : x, z, w, d = rectangle, density = trees per 1000 m2. Trees keep away from plots, roads, objects, ponds.
 trees   : count + seed = extra single trees all over the map (same seed = same trees every time)
 scatter : bush / rock / flower / bale = how many; seed. They fill every empty space (no collision).
Put your own prop scenes in res://props/<type>.tscn (root = Node3D, origin on the ground), then use "type": "<type>".
