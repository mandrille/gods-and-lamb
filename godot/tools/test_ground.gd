extends RefCounted
class_name TestGround

## Green the map, for probes that are not about the desert.
##
## A plot arrives as bare dirt now and only a player's clicks turn it green.
## That is the game, and `touch_probe` and `opening_probe` are the two files
## that should care about it. Everything else -- do two buildings overlap, does
## a priest bless a neighbour, does a passive apply -- needs a plot somebody
## could build on, and would otherwise be testing the desert by accident.
##
## Measured when this was missing: build_probe staged 0 of 20 buildings and
## reported twenty-one failures, none of which were about building placement.

## Turn every flat land tile to grass. Returns how many changed.
static func green(root) -> int:
	var n := 0
	for row in root.builder.lower.size():
		var line: String = root.builder.lower[row]
		for col in line.length():
			if line[col] != "D":
				continue
			if root.builder.set_tile(col, row, "G"):
				root.grid.set_code(Vector2i(col, row), "G")
				n += 1
	return n
