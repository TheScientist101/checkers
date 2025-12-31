extends Node2D

const PIECES = {
	"K" : Vector2i(5, 0),
	"Q" : Vector2i(4, 0),
	"R" : Vector2i(1, 0),
	"B" : Vector2i(3, 0),
	"N" : Vector2i(2, 0),
	"P" : Vector2i(0, 0),

	"k" : Vector2i(5, 1),
	"q" : Vector2i(4, 1),
	"r" : Vector2i(1, 1),
	"b" : Vector2i(3, 1),
	"n" : Vector2i(2, 1),
	"p" : Vector2i(0, 1)
}

@onready var board := $TileMap

var is_turn := false
var side := "white"

var kingside_available := true
var queenside_available := true

var en_passant_square := Vector2i(-2,-2)

enum {IDLE, SELECTED, PENDING, PROMOTING}
var mode := IDLE
var selected_coord : Vector2i

var cached_possible_moves := Dictionary()

signal promotion_selected
var promotion_select := ""

var socket := WebSocketPeer.new()

signal open

var next_expected := NONE
enum {NONE, AUTH}

var cache_token: String
var cache_email: String
var cache_url: String
var cache_uuid: String
var game_id: int



func _ready() -> void:
	set_process(false)
	$"../../../../../HTTPRequest".request_completed.connect(_on_new_game_request_recieved)

func _unhandled_input(event) -> void:
	if mode != PENDING and mode != PROMOTING:
		if is_turn:
			if event is InputEventMouseButton and event.pressed and event.button_index == 1:
				var coord : Vector2i = board.local_to_map(board.to_local(get_global_mouse_position()))
				if coord.x >= 0 and coord.x <= 7 and coord.y >= 0 and coord.y <= 7:
					if mode == IDLE:
						attempt_select(coord)
					elif mode == SELECTED:
						if board.get_cell_source_id(4, coord) == 0:
							if board.get_cell_atlas_coords(3, selected_coord).x == 0 and cached_possible_moves[coord]["promote"]:
								mode = PROMOTING
								$"../../../VBoxContainer/PromotionButtons".visible = true
								await promotion_selected
								$"../../../VBoxContainer/PromotionButtons".visible = false
								prep_move(cached_possible_moves[coord]["notation"] + promotion_select, selected_coord, coord)
							else:
								clear_indicators()
								
								prep_move(cached_possible_moves[coord]["notation"], selected_coord, coord)
						else:
							attempt_select(coord)

func prep_move(data: String, from_coord: Vector2i, to_coord: Vector2i) -> void:
	is_turn = false
	mode = IDLE
	
	board.set_cell(1, from_coord, 0, board.get_cell_atlas_coords(0, from_coord) + Vector2i(2,0))
	board.set_cell(1, to_coord, 0, board.get_cell_atlas_coords(0, to_coord) + Vector2i(2,0))
	
	send_move(data)

func make_board() -> void:
	var dark := false
	
	for i in range(8):
		for j in range(8):
			if dark:
				board.set_cell(0, Vector2i(i, j), 0, Vector2i(7, 1))
			else:
				board.set_cell(0, Vector2i(i, j), 0, Vector2i(6, 1))
			dark = !dark
		dark = !dark

func attempt_select(coord: Vector2i) -> void:
	mode = PENDING
	
	var atlas_coord = board.get_cell_atlas_coords(3, coord)
	
	if ((side == "white" and atlas_coord.y == 0) or (side == "black" and atlas_coord.y == 1)) and \
				atlas_coord.x >= 0 and atlas_coord.x <= 5:
		
		clear_indicators()
		board.set_cell(2, coord, 0, Vector2i(9, 0))
		mode = SELECTED
		selected_coord = coord
		
		cached_possible_moves = determine_possible_moves(coord)
		
		if side == "white":
			for move in cached_possible_moves.keys():
				if cached_possible_moves[move]["take"]:
					board.set_cell(4, move, 0, Vector2i(7, 0))
				else:
					board.set_cell(4, move, 0, Vector2i(6, 0))
					
		elif side == "black":
			for move in cached_possible_moves.keys():
				if cached_possible_moves[move]["take"]:
					board.set_cell(4, move, 0, Vector2i(7, 0))
				else:
					board.set_cell(4, move, 0, Vector2i(6, 0))
		
	else:
		mode = IDLE
		clear_indicators()

func clear_indicators() -> void:
	board.clear_layer(1)
	board.clear_layer(2)
	board.clear_layer(4)

func determine_possible_moves(coord: Vector2i) -> Dictionary:
	var atlas_coord = board.get_cell_atlas_coords(3, coord)
	
	var potentials := Dictionary()
	
	if atlas_coord.x == 0: # Pawn
		
		if side == "white":
			
			# Single move
			if coord.y >= 1 and cell_empty(coord - Vector2i(0,1)):
				potentials[Vector2i(coord.x, coord.y-1)] = {
					"promote" : coord.y == 1,
					"take" : false,
					"double" : false,
					"en_passant" : false
				}
			
			# Double move
			if coord.y == 6 and cell_empty(coord - Vector2i(0,1)) and cell_empty(coord - Vector2i(0,2)):
				potentials[Vector2i(coord.x, coord.y-2)] = {
					"promote" : false,
					"take" : false,
					"double" : true,
					"en_passant" : false
				}
			
			# Take
			if coord.y >= 1 and not cell_empty(coord - Vector2i(1,1)) and get_color_at(coord - Vector2i(1,1)) == "black":
				potentials[Vector2i(coord.x-1, coord.y-1)] = {
					"promote" : coord.y == 1,
					"take" : true,
					"double" : false,
					"en_passant" : false
				}
			if coord.y >= 1 and not cell_empty(coord - Vector2i(-1,1)) and get_color_at(coord - Vector2i(-1,1)) == "black":
				potentials[Vector2i(coord.x+1, coord.y-1)] = {
					"promote" : coord.y == 1,
					"take" : true,
					"double" : false,
					"en_passant" : false
				}
			
			# En Passant
			if (coord + Vector2i(-1,-1)) == en_passant_square:
				potentials[Vector2i(coord.x-1, coord.y-1)] = {
					"promote" : false,
					"take" : true,
					"double" : false,
					"en_passant" : true
				}
			if (coord + Vector2i(1,-1)) == en_passant_square:
				potentials[Vector2i(coord.x+1, coord.y-1)] = {
					"promote" : false,
					"take" : true,
					"double" : false,
					"en_passant" : true
				}
			
		elif side == "black":

			# Single move
			if coord.y >= 1 and cell_empty(coord - Vector2i(0,1)):
				potentials[Vector2i(coord.x, coord.y-1)] = {
					"promote" : coord.y == 1,
					"take" : false,
					"double" : false,
					"en_passant" : false
				}
			
			# Double move
			if coord.y == 6 and cell_empty(coord - Vector2i(0,1)) and cell_empty(coord - Vector2i(0,2)):
				potentials[Vector2i(coord.x, coord.y-2)] = {
					"promote" : false,
					"take" : false,
					"double" : true,
					"en_passant" : false
				}
			
			# Take
			if coord.y >= 1 and not cell_empty(coord - Vector2i(1,1)) and get_color_at(coord - Vector2i(1,1)) == "white":
				potentials[Vector2i(coord.x-1, coord.y-1)] = {
					"promote" : coord.y == 1,
					"take" : true,
					"double" : false,
					"en_passant" : false
				}
			if coord.y >= 1 and not cell_empty(coord - Vector2i(-1,1)) and get_color_at(coord - Vector2i(-1,1)) == "white":
				potentials[Vector2i(coord.x+1, coord.y-1)] = {
					"promote" : coord.y == 1,
					"take" : true,
					"double" : false,
					"en_passant" : false
				}
			
			# En Passant
			if (coord + Vector2i(-1,-1)) == en_passant_square:
				potentials[Vector2i(coord.x-1, coord.y-1)] = {
					"promote" : false,
					"take" : true,
					"double" : false,
					"en_passant" : true
				}
			if (coord + Vector2i(1,-1)) == en_passant_square:
				potentials[Vector2i(coord.x+1, coord.y-1)] = {
					"promote" : false,
					"take" : true,
					"double" : false,
					"en_passant" : true
				}
		
		#promote
		#check?
		#checking?
		#notation
	elif atlas_coord.x == 1: # Rook
		
		if side == "white":
			# Left
			var x := coord.x
			while x > 0:
				x -= 1
				if cell_empty(Vector2i(x, coord.y)):
					potentials[Vector2i(x, coord.y)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(x, coord.y)) == "black":
						potentials[Vector2i(x, coord.y)] = {
							"take" : true
						}
					break
			
			# Right
			x = coord.x
			while x < 7:
				x += 1
				if cell_empty(Vector2i(x, coord.y)):
					potentials[Vector2i(x, coord.y)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(x, coord.y)) == "black":
						potentials[Vector2i(x, coord.y)] = {
							"take" : true
						}
					break
					
			# Up
			var y := coord.y
			while y > 0:
				y -= 1
				if cell_empty(Vector2i(coord.x, y)):
					potentials[Vector2i(coord.x, y)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(coord.x, y)) == "black":
						potentials[Vector2i(coord.x, y)] = {
							"take" : true
						}
					break
					
			# Down
			y = coord.y
			while y < 7:
				y += 1
				if cell_empty(Vector2i(coord.x, y)):
					potentials[Vector2i(coord.x, y)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(coord.x, y)) == "black":
						potentials[Vector2i(coord.x, y)] = {
							"take" : true
						}
					break
		
		elif side == "black":
			# Left
			var x := coord.x
			while x > 0:
				x -= 1
				if cell_empty(Vector2i(x, coord.y)):
					potentials[Vector2i(x, coord.y)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(x, coord.y)) == "white":
						potentials[Vector2i(x, coord.y)] = {
							"take" : true
						}
					break
			
			# Right
			x = coord.x
			while x < 7:
				x += 1
				if cell_empty(Vector2i(x, coord.y)):
					potentials[Vector2i(x, coord.y)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(x, coord.y)) == "white":
						potentials[Vector2i(x, coord.y)] = {
							"take" : true
						}
					break
					
			# Up
			var y := coord.y
			while y > 0:
				y -= 1
				if cell_empty(Vector2i(coord.x, y)):
					potentials[Vector2i(coord.x, y)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(coord.x, y)) == "white":
						potentials[Vector2i(coord.x, y)] = {
							"take" : true
						}
					break
					
			# Down
			y = coord.y
			while y < 7:
				y += 1
				if cell_empty(Vector2i(coord.x, y)):
					potentials[Vector2i(coord.x, y)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(coord.x, y)) == "white":
						potentials[Vector2i(coord.x, y)] = {
							"take" : true
						}
					break

		#castle
		#check?
		#checking?
		#notation
	elif atlas_coord.x == 2: # Knight
		
		if side == "white":
			
			#RRU
			if coord.x <= 5 and coord.y >= 1:
				if cell_empty(coord + Vector2i(2,-1)):
					potentials[Vector2i(coord.x+2, coord.y-1)] = {
						"take" : false
					}
				elif get_color_at(coord + Vector2i(2,-1)) == "black":
					potentials[Vector2i(coord.x+2, coord.y-1)] = {
						"take" : true
					}
			
			#RRD
			if coord.x <= 5 and coord.y <= 6:
				if cell_empty(coord + Vector2i(2,1)):
					potentials[Vector2i(coord.x+2, coord.y+1)] = {
						"take" : false
					}
				elif get_color_at(coord + Vector2i(2,1)) == "black":
					potentials[Vector2i(coord.x+2, coord.y+1)] = {
						"take" : true
					}
					
			#LLU
			if coord.x >= 2 and coord.y >= 1:
				if cell_empty(coord + Vector2i(-2,-1)):
					potentials[Vector2i(coord.x-2, coord.y-1)] = {
						"take" : false
					}
				elif get_color_at(coord + Vector2i(-2,-1)) == "black":
					potentials[Vector2i(coord.x-2, coord.y-1)] = {
						"take" : true
					}
			
			#LLD
			if coord.x >= 2 and coord.y <= 6:
				if cell_empty(coord + Vector2i(-2,1)):
					potentials[Vector2i(coord.x-2, coord.y+1)] = {
						"take" : false
					}
				elif get_color_at(coord + Vector2i(-2,1)) == "black":
					potentials[Vector2i(coord.x-2, coord.y+1)] = {
						"take" : true
					}
			
			#UUR
			if coord.x <= 6 and coord.y >= 2:
				if cell_empty(coord + Vector2i(1,-2)):
					potentials[Vector2i(coord.x+1, coord.y-2)] = {
						"take" : false
					}
				elif get_color_at(coord + Vector2i(1,-2)) == "black":
					potentials[Vector2i(coord.x+1, coord.y-2)] = {
						"take" : true
					}
			
			#DDR
			if coord.x <= 6 and coord.y <= 5:
				if cell_empty(coord + Vector2i(1,2)):
					potentials[Vector2i(coord.x+1, coord.y+2)] = {
						"take" : false
					}
				elif get_color_at(coord + Vector2i(1,2)) == "black":
					potentials[Vector2i(coord.x+1, coord.y+2)] = {
						"take" : true
					}
			
			#UUL
			if coord.x >= 1 and coord.y >= 2:
				if cell_empty(coord + Vector2i(-1,-2)):
					potentials[Vector2i(coord.x-1, coord.y-2)] = {
						"take" : false
					}
				elif get_color_at(coord + Vector2i(-1,-2)) == "black":
					potentials[Vector2i(coord.x-1, coord.y-2)] = {
						"take" : true
					}
			
			#DDL
			if coord.x >= 1 and coord.y <= 5:
				if cell_empty(coord + Vector2i(-1,2)):
					potentials[Vector2i(coord.x-1, coord.y+2)] = {
						"take" : false
					}
				elif get_color_at(coord + Vector2i(-1,2)) == "black":
					potentials[Vector2i(coord.x-1, coord.y+2)] = {
						"take" : true
					}
					
		elif side == "black":
			
			#RRU
			if coord.x <= 5 and coord.y >= 1:
				if cell_empty(coord + Vector2i(2,-1)):
					potentials[Vector2i(coord.x+2, coord.y-1)] = {
						"take" : false
					}
				elif get_color_at(coord + Vector2i(2,-1)) == "white":
					potentials[Vector2i(coord.x+2, coord.y-1)] = {
						"take" : true
					}
			
			#RRD
			if coord.x <= 5 and coord.y <= 6:
				if cell_empty(coord + Vector2i(2,1)):
					potentials[Vector2i(coord.x+2, coord.y+1)] = {
						"take" : false
					}
				elif get_color_at(coord + Vector2i(2,1)) == "white":
					potentials[Vector2i(coord.x+2, coord.y+1)] = {
						"take" : true
					}
					
			#LLU
			if coord.x >= 2 and coord.y >= 1:
				if cell_empty(coord + Vector2i(-2,-1)):
					potentials[Vector2i(coord.x-2, coord.y-1)] = {
						"take" : false
					}
				elif get_color_at(coord + Vector2i(-2,-1)) == "white":
					potentials[Vector2i(coord.x-2, coord.y-1)] = {
						"take" : true
					}
			
			#LLD
			if coord.x >= 2 and coord.y <= 6:
				if cell_empty(coord + Vector2i(-2,1)):
					potentials[Vector2i(coord.x-2, coord.y+1)] = {
						"take" : false
					}
				elif get_color_at(coord + Vector2i(-2,1)) == "white":
					potentials[Vector2i(coord.x-2, coord.y+1)] = {
						"take" : true
					}
			
			#UUR
			if coord.x <= 6 and coord.y >= 2:
				if cell_empty(coord + Vector2i(1,-2)):
					potentials[Vector2i(coord.x+1, coord.y-2)] = {
						"take" : false
					}
				elif get_color_at(coord + Vector2i(1,-2)) == "white":
					potentials[Vector2i(coord.x+1, coord.y-2)] = {
						"take" : true
					}
			
			#DDR
			if coord.x <= 6 and coord.y <= 5:
				if cell_empty(coord + Vector2i(1,2)):
					potentials[Vector2i(coord.x+1, coord.y+2)] = {
						"take" : false
					}
				elif get_color_at(coord + Vector2i(1,2)) == "white":
					potentials[Vector2i(coord.x+1, coord.y+2)] = {
						"take" : true
					}
			
			#UUL
			if coord.x >= 1 and coord.y >= 2:
				if cell_empty(coord + Vector2i(-1,-2)):
					potentials[Vector2i(coord.x-1, coord.y-2)] = {
						"take" : false
					}
				elif get_color_at(coord + Vector2i(-1,-2)) == "white":
					potentials[Vector2i(coord.x-1, coord.y-2)] = {
						"take" : true
					}
			
			#DDL
			if coord.x >= 1 and coord.y <= 5:
				if cell_empty(coord + Vector2i(-1,2)):
					potentials[Vector2i(coord.x-1, coord.y+2)] = {
						"take" : false
					}
				elif get_color_at(coord + Vector2i(-1,2)) == "white":
					potentials[Vector2i(coord.x-1, coord.y+2)] = {
						"take" : true
					}
					
		#check?
		#checking?
		#notation
	elif atlas_coord.x == 3: # Bishop
		
		if side == "white":
			
			# Up Right
			var i := 0
			while coord.x + i < 7 and coord.y - i > 0:
				i += 1
				if cell_empty(Vector2i(coord.x+i, coord.y-i)):
					potentials[Vector2i(coord.x+i, coord.y-i)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(coord.x+i, coord.y-i)) == "black":
						potentials[Vector2i(coord.x+i, coord.y-i)] = {
							"take" : true
						}
					break
			
			# Down Right
			i = 0
			while coord.x + i < 7 and coord.y + i < 7:
				i += 1
				if cell_empty(Vector2i(coord.x+i, coord.y+i)):
					potentials[Vector2i(coord.x+i, coord.y+i)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(coord.x+i, coord.y+i)) == "black":
						potentials[Vector2i(coord.x+i, coord.y+i)] = {
							"take" : true
						}
					break
			
			# Down Left
			i = 0
			while coord.x - i > 0 and coord.y + i < 7:
				i += 1
				if cell_empty(Vector2i(coord.x-i, coord.y+i)):
					potentials[Vector2i(coord.x-i, coord.y+i)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(coord.x-i, coord.y+i)) == "black":
						potentials[Vector2i(coord.x-i, coord.y+i)] = {
							"take" : true
						}
					break
				
			# Up Left
			i = 0
			while coord.x - i > 0 and coord.y - i > 0:
				i += 1
				if cell_empty(Vector2i(coord.x-i, coord.y-i)):
					potentials[Vector2i(coord.x-i, coord.y-i)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(coord.x-i, coord.y-i)) == "black":
						potentials[Vector2i(coord.x-i, coord.y-i)] = {
							"take" : true
						}
					break
		
		elif side == "black":
			
			# Up Right
			var i := 0
			while coord.x + i < 7 and coord.y - i > 0:
				i += 1
				if cell_empty(Vector2i(coord.x+i, coord.y-i)):
					potentials[Vector2i(coord.x+i, coord.y-i)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(coord.x+i, coord.y-i)) == "white":
						potentials[Vector2i(coord.x+i, coord.y-i)] = {
							"take" : true
						}
					break
			
			# Down Right
			i = 0
			while coord.x + i < 7 and coord.y + i < 7:
				i += 1
				if cell_empty(Vector2i(coord.x+i, coord.y+i)):
					potentials[Vector2i(coord.x+i, coord.y+i)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(coord.x+i, coord.y+i)) == "white":
						potentials[Vector2i(coord.x+i, coord.y+i)] = {
							"take" : true
						}
					break
			
			# Down Left
			i = 0
			while coord.x - i > 0 and coord.y + i < 7:
				i += 1
				if cell_empty(Vector2i(coord.x-i, coord.y+i)):
					potentials[Vector2i(coord.x-i, coord.y+i)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(coord.x-i, coord.y+i)) == "white":
						potentials[Vector2i(coord.x-i, coord.y+i)] = {
							"take" : true
						}
					break
				
			# Up Left
			i = 0
			while coord.x - i > 0 and coord.y - i > 0:
				i += 1
				if cell_empty(Vector2i(coord.x-i, coord.y-i)):
					potentials[Vector2i(coord.x-i, coord.y-i)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(coord.x-i, coord.y-i)) == "white":
						potentials[Vector2i(coord.x-i, coord.y-i)] = {
							"take" : true
						}
					break

		#check?
		#checking?
		#notation
	elif atlas_coord.x == 4: # Queen
		
		if side == "white":
			# Left
			var x := coord.x
			while x > 0:
				x -= 1
				if cell_empty(Vector2i(x, coord.y)):
					potentials[Vector2i(x, coord.y)] = {
						"take" : false,
						"castle" : 0
					}
				else:
					if get_color_at(Vector2i(x, coord.y)) == "black":
						potentials[Vector2i(x, coord.y)] = {
							"take" : true,
							"castle" : 0
						}
					break
			
			# Right
			x = coord.x
			while x < 7:
				x += 1
				if cell_empty(Vector2i(x, coord.y)):
					potentials[Vector2i(x, coord.y)] = {
						"take" : false,
						"castle" : 0
					}
				else:
					if get_color_at(Vector2i(x, coord.y)) == "black":
						potentials[Vector2i(x, coord.y)] = {
							"take" : true,
							"castle" : 0
						}
					break
					
			# Up
			var y := coord.y
			while y > 0:
				y -= 1
				if cell_empty(Vector2i(coord.x, y)):
					potentials[Vector2i(coord.x, y)] = {
						"take" : false,
						"castle" : 0
					}
				else:
					if get_color_at(Vector2i(coord.x, y)) == "black":
						potentials[Vector2i(coord.x, y)] = {
							"take" : true,
							"castle" : 0
						}
					break
					
			# Down
			y = coord.y
			while y < 7:
				y += 1
				if cell_empty(Vector2i(coord.x, y)):
					potentials[Vector2i(coord.x, y)] = {
						"take" : false,
						"castle" : 0
					}
				else:
					if get_color_at(Vector2i(coord.x, y)) == "black":
						potentials[Vector2i(coord.x, y)] = {
							"take" : true,
							"castle" : 0
						}
					break
			
			# Up Right
			var i := 0
			while coord.x + i < 7 and coord.y - i > 0:
				i += 1
				if cell_empty(Vector2i(coord.x+i, coord.y-i)):
					potentials[Vector2i(coord.x+i, coord.y-i)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(coord.x+i, coord.y-i)) == "black":
						potentials[Vector2i(coord.x+i, coord.y-i)] = {
							"take" : true
						}
					break
			
			# Down Right
			i = 0
			while coord.x + i < 7 and coord.y + i < 7:
				i += 1
				if cell_empty(Vector2i(coord.x+i, coord.y+i)):
					potentials[Vector2i(coord.x+i, coord.y+i)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(coord.x+i, coord.y+i)) == "black":
						potentials[Vector2i(coord.x+i, coord.y+i)] = {
							"take" : true
						}
					break
			
			# Down Left
			i = 0
			while coord.x - i > 0 and coord.y + i < 7:
				i += 1
				if cell_empty(Vector2i(coord.x-i, coord.y+i)):
					potentials[Vector2i(coord.x-i, coord.y+i)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(coord.x-i, coord.y+i)) == "black":
						potentials[Vector2i(coord.x-i, coord.y+i)] = {
							"take" : true
						}
					break
				
			# Up Left
			i = 0
			while coord.x - i > 0 and coord.y - i > 0:
				i += 1
				if cell_empty(Vector2i(coord.x-i, coord.y-i)):
					potentials[Vector2i(coord.x-i, coord.y-i)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(coord.x-i, coord.y-i)) == "black":
						potentials[Vector2i(coord.x-i, coord.y-i)] = {
							"take" : true
						}
					break
					
		elif side == "black":
				
			# Left
			var x := coord.x
			while x > 0:
				x -= 1
				if cell_empty(Vector2i(x, coord.y)):
					potentials[Vector2i(x, coord.y)] = {
						"take" : false,
						"castle" : 0
					}
				else:
					if get_color_at(Vector2i(x, coord.y)) == "white":
						potentials[Vector2i(x, coord.y)] = {
							"take" : true,
							"castle" : 0
						}
					break
			
			# Right
			x = coord.x
			while x < 7:
				x += 1
				if cell_empty(Vector2i(x, coord.y)):
					potentials[Vector2i(x, coord.y)] = {
						"take" : false,
						"castle" : 0
					}
				else:
					if get_color_at(Vector2i(x, coord.y)) == "white":
						potentials[Vector2i(x, coord.y)] = {
							"take" : true,
							"castle" : 0
						}
					break
					
			# Up
			var y := coord.y
			while y > 0:
				y -= 1
				if cell_empty(Vector2i(coord.x, y)):
					potentials[Vector2i(coord.x, y)] = {
						"take" : false,
						"castle" : 0
					}
				else:
					if get_color_at(Vector2i(coord.x, y)) == "white":
						potentials[Vector2i(coord.x, y)] = {
							"take" : true,
							"castle" : 0
						}
					break
					
			# Down
			y = coord.y
			while y < 7:
				y += 1
				if cell_empty(Vector2i(coord.x, y)):
					potentials[Vector2i(coord.x, y)] = {
						"take" : false,
						"castle" : 0
					}
				else:
					if get_color_at(Vector2i(coord.x, y)) == "white":
						potentials[Vector2i(coord.x, y)] = {
							"take" : true,
							"castle" : 0
						}
					break
			
			# Up Right
			var i := 0
			while coord.x + i < 7 and coord.y - i > 0:
				i += 1
				if cell_empty(Vector2i(coord.x+i, coord.y-i)):
					potentials[Vector2i(coord.x+i, coord.y-i)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(coord.x+i, coord.y-i)) == "white":
						potentials[Vector2i(coord.x+i, coord.y-i)] = {
							"take" : true
						}
					break
			
			# Down Right
			i = 0
			while coord.x + i < 7 and coord.y + i < 7:
				i += 1
				if cell_empty(Vector2i(coord.x+i, coord.y+i)):
					potentials[Vector2i(coord.x+i, coord.y+i)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(coord.x+i, coord.y+i)) == "white":
						potentials[Vector2i(coord.x+i, coord.y+i)] = {
							"take" : true
						}
					break
			
			# Down Left
			i = 0
			while coord.x - i > 0 and coord.y + i < 7:
				i += 1
				if cell_empty(Vector2i(coord.x-i, coord.y+i)):
					potentials[Vector2i(coord.x-i, coord.y+i)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(coord.x-i, coord.y+i)) == "white":
						potentials[Vector2i(coord.x-i, coord.y+i)] = {
							"take" : true
						}
					break
				
			# Up Left
			i = 0
			while coord.x - i > 0 and coord.y - i > 0:
				i += 1
				if cell_empty(Vector2i(coord.x-i, coord.y-i)):
					potentials[Vector2i(coord.x-i, coord.y-i)] = {
						"take" : false
					}
				else:
					if get_color_at(Vector2i(coord.x-i, coord.y-i)) == "white":
						potentials[Vector2i(coord.x-i, coord.y-i)] = {
							"take" : true
						}
					break
		
		#check?
		#checking?
		#notation
	elif atlas_coord.x == 5: # King
		
		if side == "white":
			
			# Up
			if coord.y >= 1:
				if cell_empty(coord + Vector2i(0,-1)):
					potentials[Vector2i(coord.x, coord.y-1)] = {
						"take" : false,
						"castle" : 0
					}
				elif get_color_at(coord + Vector2i(0,-1)) == "black":
					potentials[Vector2i(coord.x, coord.y-1)] = {
						"take" : true,
						"castle" : 0
					}
			
			# Down
			if coord.y <= 6:
				if cell_empty(coord + Vector2i(0,1)):
					potentials[Vector2i(coord.x, coord.y+1)] = {
						"take" : false,
						"castle" : 0
					}
				elif get_color_at(coord + Vector2i(0,1)) == "black":
					potentials[Vector2i(coord.x, coord.y+1)] = {
						"take" : true,
						"castle" : 0
					}
			
			# Left
			if coord.x >= 1:
				if cell_empty(coord + Vector2i(-1,0)):
					potentials[Vector2i(coord.x-1, coord.y)] = {
						"take" : false,
						"castle" : 0
					}
				elif get_color_at(coord + Vector2i(-1,0)) == "black":
					potentials[Vector2i(coord.x-1, coord.y)] = {
						"take" : true,
						"castle" : 0
					}
			
			# Right
			if coord.x <= 6:
				if cell_empty(coord + Vector2i(1,0)):
					potentials[Vector2i(coord.x+1, coord.y)] = {
						"take" : false,
						"castle" : 0
					}
				elif get_color_at(coord + Vector2i(1,0)) == "black":
					potentials[Vector2i(coord.x+1, coord.y)] = {
						"take" : true,
						"castle" : 0
					}
			
			# Up Right
			if coord.x <= 6 and coord.y >= 1:
				if cell_empty(coord + Vector2i(1,-1)):
					potentials[Vector2i(coord.x+1, coord.y-1)] = {
						"take" : false,
						"castle" : 0
					}
				elif get_color_at(coord + Vector2i(1,-1)) == "black":
					potentials[Vector2i(coord.x+1, coord.y-1)] = {
						"take" : true,
						"castle" : 0
					}
			
			# Down Right
			if coord.x <= 6 and coord.y <= 6:
				if cell_empty(coord + Vector2i(1,1)):
					potentials[Vector2i(coord.x+1, coord.y+1)] = {
						"take" : false,
						"castle" : 0
					}
				elif get_color_at(coord + Vector2i(1,1)) == "black":
					potentials[Vector2i(coord.x+1, coord.y+1)] = {
						"take" : true,
						"castle" : 0
					}
			
			# Down Left
			if coord.x >= 1 and coord.y <= 6:
				if cell_empty(coord + Vector2i(-1,1)):
					potentials[Vector2i(coord.x-1, coord.y+1)] = {
						"take" : false,
						"castle" : 0
					}
				elif get_color_at(coord + Vector2i(-1,1)) == "black":
					potentials[Vector2i(coord.x-1, coord.y+1)] = {
						"take" : true,
						"castle" : 0
					}
			
			# Up Left
			if coord.x >= 1 and coord.y >= 1:
				if cell_empty(coord + Vector2i(-1,-1)):
					potentials[Vector2i(coord.x-1, coord.y-1)] = {
						"take" : false,
						"castle" : 0
					}
				elif get_color_at(coord + Vector2i(-1,-1)) == "black":
					potentials[Vector2i(coord.x-1, coord.y-1)] = {
						"take" : true,
						"castle" : 0
					}
			
			# Castle
			if kingside_available:
				if cell_empty(Vector2i(5,7)) and cell_empty(Vector2i(6,7)):
					potentials[Vector2i(6,7)] = {
						"take" : false,
						"castle" : 1
					}
			if queenside_available:
				if cell_empty(Vector2i(3,7)) and cell_empty(Vector2i(2,7)) and cell_empty(Vector2i(1,7)):
					potentials[Vector2i(2,7)] = {
						"take" : false,
						"castle" : 2
					}
					
		elif side == "black":
				
			# Up
			if coord.y >= 1:
				if cell_empty(coord + Vector2i(0,-1)):
					potentials[Vector2i(coord.x, coord.y-1)] = {
						"take" : false,
						"castle" : 0
					}
				elif get_color_at(coord + Vector2i(0,-1)) == "white":
					potentials[Vector2i(coord.x, coord.y-1)] = {
						"take" : true,
						"castle" : 0
					}
			
			# Down
			if coord.y <= 6:
				if cell_empty(coord + Vector2i(0,1)):
					potentials[Vector2i(coord.x, coord.y+1)] = {
						"take" : false,
						"castle" : 0
					}
				elif get_color_at(coord + Vector2i(0,1)) == "white":
					potentials[Vector2i(coord.x, coord.y+1)] = {
						"take" : true,
						"castle" : 0
					}
			
			# Left
			if coord.x >= 1:
				if cell_empty(coord + Vector2i(-1,0)):
					potentials[Vector2i(coord.x-1, coord.y)] = {
						"take" : false,
						"castle" : 0
					}
				elif get_color_at(coord + Vector2i(-1,0)) == "white":
					potentials[Vector2i(coord.x-1, coord.y)] = {
						"take" : true,
						"castle" : 0
					}
			
			# Right
			if coord.x <= 6:
				if cell_empty(coord + Vector2i(1,0)):
					potentials[Vector2i(coord.x+1, coord.y)] = {
						"take" : false,
						"castle" : 0
					}
				elif get_color_at(coord + Vector2i(1,0)) == "white":
					potentials[Vector2i(coord.x+1, coord.y)] = {
						"take" : true,
						"castle" : 0
					}
			
			# Up Right
			if coord.x <= 6 and coord.y >= 1:
				if cell_empty(coord + Vector2i(1,-1)):
					potentials[Vector2i(coord.x+1, coord.y-1)] = {
						"take" : false,
						"castle" : 0
					}
				elif get_color_at(coord + Vector2i(1,-1)) == "white":
					potentials[Vector2i(coord.x+1, coord.y-1)] = {
						"take" : true,
						"castle" : 0
					}
			
			# Down Right
			if coord.x <= 6 and coord.y <= 6:
				if cell_empty(coord + Vector2i(1,1)):
					potentials[Vector2i(coord.x+1, coord.y+1)] = {
						"take" : false,
						"castle" : 0
					}
				elif get_color_at(coord + Vector2i(1,1)) == "white":
					potentials[Vector2i(coord.x+1, coord.y+1)] = {
						"take" : true,
						"castle" : 0
					}
			
			# Down Left
			if coord.x >= 1 and coord.y <= 6:
				if cell_empty(coord + Vector2i(-1,1)):
					potentials[Vector2i(coord.x-1, coord.y+1)] = {
						"take" : false,
						"castle" : 0
					}
				elif get_color_at(coord + Vector2i(-1,1)) == "white":
					potentials[Vector2i(coord.x-1, coord.y+1)] = {
						"take" : true,
						"castle" : 0
					}
			
			# Up Left
			if coord.x >= 1 and coord.y >= 1:
				if cell_empty(coord + Vector2i(-1,-1)):
					potentials[Vector2i(coord.x-1, coord.y-1)] = {
						"take" : false,
						"castle" : 0
					}
				elif get_color_at(coord + Vector2i(-1,-1)) == "white":
					potentials[Vector2i(coord.x-1, coord.y-1)] = {
						"take" : true,
						"castle" : 0
					}
			
			# Castle
			if kingside_available:
				if cell_empty(Vector2i(1,7)) and cell_empty(Vector2i(2,7)):
					potentials[Vector2i(1,7)] = {
						"take" : false,
						"castle" : 1
					}
			if queenside_available:
				if cell_empty(Vector2i(6,7)) and cell_empty(Vector2i(5,7)) and cell_empty(Vector2i(4,7)):
					potentials[Vector2i(6,7)] = {
						"take" : false,
						"castle" : 2
					}
		
		#castle?
		#check?
		#checking?????
		#notation
	
	for key in potentials.keys():
		if atlas_coord.x == 5 and potentials[key]["castle"] == 1:
			if side == "white":
				if check_check(coord, key, Vector2i(7,7), Vector2i(5,7)):
					potentials.erase(key)
			elif side == "black":
				if check_check(coord, key, Vector2i(0,7), Vector2i(2,7)):
					potentials.erase(key)
		elif atlas_coord.x == 5 and potentials[key]["castle"] == 2:
			if side == "white":
				if check_check(coord, key, Vector2i(0,7), Vector2i(3,7)):
					potentials.erase(key)
			elif side == "black":
				if check_check(coord, key, Vector2i(7,7), Vector2i(4,7)):
					potentials.erase(key)
		else:
			if check_check(coord, key):
				potentials.erase(key)
	
	for key in potentials.keys():
		potentials[key]["notation"] = generate_uci_positional(coord, key)
	
	return potentials

func check_check(from_position: Vector2i, to_position: Vector2i, extra_from_position: Vector2i = Vector2i(-1,-1), extra_to_position: Vector2i = Vector2i(-1,-1)) -> bool:
	var board_copy : TileMap = board.duplicate()
	
	var atlas_coord : Vector2i = board_copy.get_cell_atlas_coords(3, from_position)
	board_copy.set_cell(3, from_position, -1)
	board_copy.set_cell(3, to_position, 0, atlas_coord)
	
	if extra_from_position != Vector2i(-1,-1):
		var extra_atlas_coord : Vector2i = board_copy.get_cell_atlas_coords(3, extra_from_position)
		board_copy.set_cell(3, extra_from_position, -1)
		if extra_to_position != Vector2i(-1,-1):
			board_copy.set_cell(3, extra_to_position, 0, extra_atlas_coord)
	
	if side == "white":
		var king_coord: Vector2i
		var done := false
		for i in range(8):
			for j in range(8):
				if board_copy.get_cell_atlas_coords(3, Vector2i(i, j)) == Vector2i(5, 0):
					king_coord = Vector2i(i, j)
					break
			if done: break
		
		# Left (Multiple)
		var i := 0
		while king_coord.x - i > 0:
			i += 1
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(-i,0)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(-i,0))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 1 or potential_atlas_coord.x == 4:
						return true
					else:
						break
				else:
					break
					
		# Right (Multiple)
		i = 0
		while king_coord.x + i < 7:
			i += 1
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(i,0)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(i,0))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 1 or potential_atlas_coord.x == 4:
						return true
					else:
						break
				else:
					break
		
		# Up (Multiple)
		i = 0
		while king_coord.y - i > 0:
			i += 1
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(0,-i)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(0,-i))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 1 or potential_atlas_coord.x == 4:
						return true
					else:
						break
				else:
					break
		
		# Down (Multiple)
		i = 0
		while king_coord.y + i < 7:
			i += 1
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(0,i)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(0,i))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 1 or potential_atlas_coord.x == 4:
						return true
					else:
						break
				else:
					break
		
		# Up Left (Multiple)
		i = 0
		while king_coord.x - i > 0 and king_coord.y - i > 0:
			i += 1
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(-i,-i)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(-i,-i))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 3 or potential_atlas_coord.x == 4:
						return true
					else:
						break
				else:
					break
		
		# Up Right (Multiple)
		i = 0
		while king_coord.x + i < 7 and king_coord.y - i > 0:
			i += 1
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(i,-i)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(i,-i))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 3 or potential_atlas_coord.x == 4:
						return true
					else:
						break
				else:
					break
		
		# Down Right (Multiple)
		i = 0
		while king_coord.x + i < 7 and king_coord.y + i < 7:
			i += 1
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(i,i)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(i,i))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 3 or potential_atlas_coord.x == 4:
						return true
					else:
						break
				else:
					break
		
		# Down Left (Multiple)
		i = 0
		while king_coord.x - i > 0 and king_coord.y + i < 7:
			i += 1
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(-i,i)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(-i,i))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 3 or potential_atlas_coord.x == 4:
						return true
					else:
						break
				else:
					break
		
		#RRU
		if king_coord.x <= 5 and king_coord.y >= 1:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(2,-1)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, Vector2i(king_coord.x+2, king_coord.y-1))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 2:
						return true
		
		#RRD
		if king_coord.x <= 5 and king_coord.y <= 6:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(2,1)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, Vector2i(king_coord.x+2, king_coord.y+1))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 2:
						return true
				
		#LLU
		if king_coord.x >= 2 and king_coord.y >= 1:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(-2,-1)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, Vector2i(king_coord.x-2, king_coord.y-1))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 2:
						return true
		
		#LLD
		if king_coord.x >= 2 and king_coord.y <= 6:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(-2,1)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, Vector2i(king_coord.x-2, king_coord.y+1))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 2:
						return true
		
		#UUR
		if king_coord.x <= 6 and king_coord.y >= 2:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(1,-2)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, Vector2i(king_coord.x+1, king_coord.y-2))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 2:
						return true
		
		#DDR
		if king_coord.x <= 6 and king_coord.y <= 5:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(1,2)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, Vector2i(king_coord.x+1, king_coord.y+2))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 2:
						return true
		
		#UUL
		if king_coord.x >= 1 and king_coord.y >= 2:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(-1,-2)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, Vector2i(king_coord.x-1, king_coord.y-2))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 2:
						return true
		
		#DDL
		if king_coord.x >= 1 and king_coord.y <= 5:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(-1,2)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, Vector2i(king_coord.x-1, king_coord.y+2))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 2:
						return true
		
		# Up (single)
		if king_coord.y > 0:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(0,-1)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(0,-1))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 5:
						return true
		
		# Down (single)
		if king_coord.y < 7:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(0,1)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(0,1))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 5:
						return true
		
		# Right (single)
		if king_coord.x < 7:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(1,0)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(1,0))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 5:
						return true
		
		# Left (single)
		if king_coord.x > 0:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(-1,0)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(-1,0))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 5:
						return true
		
		# Up Left (single)
		if king_coord.x > 0 and king_coord.y > 0:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(-1,-1)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(-1,-1))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 5 or potential_atlas_coord.x == 0:
						return true
		
		# Up Right (single)
		if king_coord.x < 7 and king_coord.y > 0:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(1,-1)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(1,-1))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 5 or potential_atlas_coord.x == 0:
						return true
		
		# Down Right (single)
		if king_coord.x < 7 and king_coord.y < 7:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(1,1)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(1,1))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 5:
						return true
		
		# Down Left (single)
		if king_coord.x > 0 and king_coord.y < 7:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(-1,1)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(-1,1))
				if potential_atlas_coord.y == 1:
					if potential_atlas_coord.x == 5:
						return true
		
	elif side == "black":
		var king_coord: Vector2i
		var done := false
		for i in range(8):
			for j in range(8):
				if board_copy.get_cell_atlas_coords(3, Vector2i(i, j)) == Vector2i(5, 1):
					king_coord = Vector2i(i, j)
					break
			if done: break
			
		# Left (Multiple)
		var i := 0
		while king_coord.x - i > 0:
			i += 1
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(-i,0)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(-i,0))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 1 or potential_atlas_coord.x == 4:
						return true
					else:
						break
				else:
					break
					
		# Right (Multiple)
		i = 0
		while king_coord.x + i < 7:
			i += 1
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(i,0)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(i,0))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 1 or potential_atlas_coord.x == 4:
						return true
					else:
						break
				else:
					break
		
		# Up (Multiple)
		i = 0
		while king_coord.y - i > 0:
			i += 1
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(0,-i)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(0,-i))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 1 or potential_atlas_coord.x == 4:
						return true
					else:
						break
				else:
					break
		
		# Down (Multiple)
		i = 0
		while king_coord.y + i < 7:
			i += 1
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(0,i)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(0,i))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 1 or potential_atlas_coord.x == 4:
						return true
					else:
						break
				else:
					break
		
		# Up Left (Multiple)
		i = 0
		while king_coord.x - i > 0 and king_coord.y - i > 0:
			i += 1
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(-i,-i)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(-i,-i))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 3 or potential_atlas_coord.x == 4:
						return true
					else:
						break
				else:
					break
		
		# Up Right (Multiple)
		i = 0
		while king_coord.x + i < 7 and king_coord.y - i > 0:
			i += 1
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(i,-i)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(i,-i))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 3 or potential_atlas_coord.x == 4:
						return true
					else:
						break
				else:
					break
		
		# Down Right (Multiple)
		i = 0
		while king_coord.x + i < 7 and king_coord.y + i < 7:
			i += 1
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(i,i)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(i,i))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 3 or potential_atlas_coord.x == 4:
						return true
					else:
						break
				else:
					break
		
		# Down Left (Multiple)
		i = 0
		while king_coord.x - i > 0 and king_coord.y + i < 7:
			i += 1
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(-i,i)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(-i,i))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 3 or potential_atlas_coord.x == 4:
						return true
					else:
						break
				else:
					break
		
		#RRU
		if king_coord.x <= 5 and king_coord.y >= 1:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(2,-1)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, Vector2i(king_coord.x+2, king_coord.y-1))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 2:
						return true
		
		#RRD
		if king_coord.x <= 5 and king_coord.y <= 6:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(2,1)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, Vector2i(king_coord.x+2, king_coord.y+1))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 2:
						return true
				
		#LLU
		if king_coord.x >= 2 and king_coord.y >= 1:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(-2,-1)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, Vector2i(king_coord.x-2, king_coord.y-1))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 2:
						return true
		
		#LLD
		if king_coord.x >= 2 and king_coord.y <= 6:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(-2,1)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, Vector2i(king_coord.x-2, king_coord.y+1))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 2:
						return true
		
		#UUR
		if king_coord.x <= 6 and king_coord.y >= 2:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(1,-2)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, Vector2i(king_coord.x+1, king_coord.y-2))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 2:
						return true
		
		#DDR
		if king_coord.x <= 6 and king_coord.y <= 5:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(1,2)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, Vector2i(king_coord.x+1, king_coord.y+2))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 2:
						return true
		
		#UUL
		if king_coord.x >= 1 and king_coord.y >= 2:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(-1,-2)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, Vector2i(king_coord.x-1, king_coord.y-2))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 2:
						return true
		
		#DDL
		if king_coord.x >= 1 and king_coord.y <= 5:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(-1,2)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, Vector2i(king_coord.x-1, king_coord.y+2))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 2:
						return true
		
		# Up (single)
		if king_coord.y > 0:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(0,-1)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(0,-1))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 5:
						return true
		
		# Down (single)
		if king_coord.y < 7:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(0,1)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(0,1))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 5:
						return true
		
		# Right (single)
		if king_coord.x < 7:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(1,0)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(1,0))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 5:
						return true
		
		# Left (single)
		if king_coord.x > 0:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(-1,0)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(-1,0))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 5:
						return true
		
		# Up Left (single)
		if king_coord.x > 0 and king_coord.y > 0:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(-1,-1)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(-1,-1))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 5 or potential_atlas_coord.x == 0:
						return true
		
		# Up Right (single)
		if king_coord.x < 7 and king_coord.y > 0:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(1,-1)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(1,-1))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 5 or potential_atlas_coord.x == 0:
						return true
		
		# Down Right (single)
		if king_coord.x < 7 and king_coord.y < 7:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(1,1)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(1,1))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 5:
						return true
		
		# Down Left (single)
		if king_coord.x > 0 and king_coord.y < 7:
			if board_copy.get_cell_source_id(3, king_coord + Vector2i(-1,1)) != -1:
				var potential_atlas_coord = board_copy.get_cell_atlas_coords(3, king_coord + Vector2i(-1,1))
				if potential_atlas_coord.y == 0:
					if potential_atlas_coord.x == 5:
						return true
	
	return false

func generate_uci_positional(from_position: Vector2i, to_position: Vector2i) -> String:
	var ret := ""
	
	if side == "white":
		match from_position.x:
			0 : ret += "a"
			1 : ret += "b"
			2 : ret += "c"
			3 : ret += "d"
			4 : ret += "e"
			5 : ret += "f"
			6 : ret += "g"
			7 : ret += "h"
		ret += str(8 - from_position.y)
		
		match to_position.x:
			0 : ret += "a"
			1 : ret += "b"
			2 : ret += "c"
			3 : ret += "d"
			4 : ret += "e"
			5 : ret += "f"
			6 : ret += "g"
			7 : ret += "h"
		ret += str(8 - to_position.y)
	
	elif side == "black":
		match from_position.x:
			0 : ret += "h"
			1 : ret += "g"
			2 : ret += "f"
			3 : ret += "e"
			4 : ret += "d"
			5 : ret += "c"
			6 : ret += "b"
			7 : ret += "a"
		ret += str(1 + from_position.y)
		
		match to_position.x:
			0 : ret += "h"
			1 : ret += "g"
			2 : ret += "f"
			3 : ret += "e"
			4 : ret += "d"
			5 : ret += "c"
			6 : ret += "b"
			7 : ret += "a"
		ret += str(1 + to_position.y)
	
	return ret

func get_color_at(coord: Vector2i) -> String:
	if board.get_cell_atlas_coords(3, coord).y == 0:
		return "white"
	return "black"
	
func cell_empty(coord: Vector2i) -> bool:
	return board.get_cell_source_id(3, coord) == -1



func set_up(side_color: String, info: String) -> void:
	side = side_color
	
	if side == "black":
		$"../../../VBoxContainer/PromotionButtons/HBoxContainer/KnightButton".icon.region.position.y = 32
		$"../../../VBoxContainer/PromotionButtons/HBoxContainer/RookButton".icon.region.position.y = 32
		$"../../../VBoxContainer/PromotionButtons/HBoxContainer/BishopButton".icon.region.position.y = 32
		$"../../../VBoxContainer/PromotionButtons/HBoxContainer/QueenButton".icon.region.position.y = 32
	
	$"../../../VBoxContainer/InfoLabel".text = info
	
	make_board()

func update_fen(fen: String) -> void:
	board.clear_layer(3)
	clear_indicators()
	
	var sections = fen.split(" ")
	
	var lines = sections[0].split("/")
	if side == "white":
		for i in range(8):
			var ind := 0
			for c : String in lines[i].split(""):
				if c.is_valid_float():
					ind += int(c)
				else:
					board.set_cell(3, Vector2i(ind, i), 0, PIECES[c])
					ind += 1
	elif side == "black":
		for i in range(8):
			lines[7-i] = lines[7-i].reverse()
			var ind := 0
			for c : String in lines[7-i].split(""):
				if c.is_valid_float():
					ind += int(c)
				else:
					board.set_cell(3, Vector2i(ind, i), 0, PIECES[c])
					ind += 1
	
	if side == "white":
		is_turn = (sections[1] == "w")
		kingside_available = sections[2].contains("K")
		queenside_available = sections[2].contains("Q")
		
	elif side == "black":
		is_turn = (sections[1] == "b")
		kingside_available = sections[2].contains("k")
		queenside_available = sections[2].contains("q")
	
	if sections[3] == "-":
		en_passant_square = Vector2i(-1,-1)
	else:
		var col: int
		match sections[3][0]:
			"a": col = 0
			"b": col = 1
			"c": col = 2
			"d": col = 3
			"e": col = 4
			"f": col = 5
			"g": col = 6
			"h": col = 7
		en_passant_square = Vector2i(col, 8 - int(sections[3][1]))
		if side == "black":
			en_passant_square = Vector2i(7,7) - en_passant_square

func send_move(data: String) -> void:
	
	var json = {
		"type" : "move",
		"payload" : {
			"notation" : data,
			"request_draw" : false,
			"resign" : false,
			"notation_type" : "uci",
			"game_id" : game_id
		}
	}
	
	socket.send_text(JSON.stringify(json))

func _process(_delta) -> void:
	# Call this in _process or _physics_process. Data transfer and state updates
	# will only happen when calling this function.
	socket.poll()
	
	# get_ready_state() tells you what state the socket is in.
	var state = socket.get_ready_state()
	
	# WebSocketPeer.STATE_OPEN means the socket is connected and ready
	# to send and receive data.
	if state == WebSocketPeer.STATE_OPEN:
		open.emit()
		while socket.get_available_packet_count():
			var packet_string = socket.get_packet().get_string_from_utf8()
			
			var json = JSON.parse_string(packet_string)
			
			if next_expected == AUTH:
				if json["success"]:
					$"../../../../../NewGame".visible = true
				next_expected = NONE
			
			else:
				if json.has("type"):
					if json["type"] == "game_start":
						game_id = json["payload"]["ID"]
						if json["payload"]["PlayerWhite"] == cache_uuid:
							set_up("white", "")
						else:
							set_up("black", "")
						
						update_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
						
						visible = true
						$"../../../../../LoadingIndicator".visible = false
						$"../../../../../NewGame".visible = false
						$"../../..".visible = true
					
					elif json["type"] == "game_board":
						update_fen(json["fen"])
					
					elif json["type"] == "move":
						
						var temp_dict = {
							"type" : "position"
						}
						
						socket.send_text(JSON.stringify(temp_dict))
					
					elif json["type"] == "game_result":
						if json["payload"]["is_draw"]:
							$"../../../../../CenterContainer/VBoxContainer/WinLabel".text = "You drew."
						elif json["payload"]["winner"] == cache_uuid:
							$"../../../../../CenterContainer/VBoxContainer/WinLabel".text = "You win!!!!!!!!!!!!"
						else:
							$"../../../../../CenterContainer/VBoxContainer/WinLabel".text = "Better luck next time!"
						
						$"../../../../../CenterContainer/VBoxContainer/WinLabel".visible = true
						$"../../../../../CenterContainer/VBoxContainer/WinButton".visible = true
						visible = false
						$"../../..".visible = false
	
	# WebSocketPeer.STATE_CLOSING means the socket is closing.
	# It is important to keep polling for a clean close.
	elif state == WebSocketPeer.STATE_CLOSING:
		pass
	
	# WebSocketPeer.STATE_CLOSED means the connection has fully closed.
	# It is now safe to stop polling.
	elif state == WebSocketPeer.STATE_CLOSED:
		# The code will be -1 if the disconnection was not properly notified by the remote peer.
		var code = socket.get_close_code()
		print("WebSocket closed with code: %d. Clean: %s" % [code, code != -1])
		set_process(false) # Stop processing.

func start(access_token: String, email: String, url: String, uuid: String) -> void:
	cache_token = access_token
	cache_email = email
	cache_url = url
	cache_uuid = uuid
	
	if connect_to_websocket("wss://" + url + "/events"):
		
		set_process(true)
		
		await open
		
		var data := {
			"access_token" : access_token,
			"email" : email
		}
		
		next_expected = AUTH
		socket.send_text(JSON.stringify(data))

func connect_to_websocket(url: String) -> bool:
	# Initiate connection to the given URL.
	var err = socket.connect_to_url(url)
	if err != OK:
		print("Unable to connect")
		return false
	return true

func _on_new_game_pressed():
	$"../../../../../NewGame".disabled = true
	
	var header = PackedStringArray()
	header.append("Authorization: " + cache_token)
	
	$"../../../../../HTTPRequest".request("https://" + cache_url + "/matchmaking?email=" + cache_email.uri_encode(), header, HTTPClient.METHOD_GET)

func _on_new_game_request_recieved(_result, _response_code, _headers, body) -> void:
	var json = JSON.parse_string(body.get_string_from_utf8())
	
	if json["success"]:
		$"../../../../../NewGame".visible = false
		if !$"../../..".visible:
			$"../../../../../LoadingIndicator".visible = true
	else:
		$"../../../../../NewGame".disabled = false



func _on_knight_button_pressed() -> void:
	promotion_select = "k"
	promotion_selected.emit()
func _on_rook_button_pressed() -> void:
	promotion_select = "r"
	promotion_selected.emit()
func _on_bishop_button_pressed() -> void:
	promotion_select = "b"
	promotion_selected.emit()
func _on_queen_button_pressed() -> void:
	promotion_select = "q"
	promotion_selected.emit()

func _on_win_button_pressed():
	$"../../../../../CenterContainer/VBoxContainer/WinLabel".visible = false
	$"../../../../../CenterContainer/VBoxContainer/WinButton".visible = false
	$"../../../../../NewGame".disabled = false
	$"../../../../../NewGame".visible = true
