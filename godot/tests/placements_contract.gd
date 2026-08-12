extends SceneTree
## Headless producer fixture for tests/test_placements_contract.py.
##
## This deliberately calls the production serializer with real PlacedObject nodes. The Python
## harness passes its output to ModForge, so this file must not duplicate placements.json itself.


func _initialize() -> void:
	# SceneTree's root exists during _initialize, but newly-added Node3D children are not inside the
	# tree until the first deferred turn; global_position would otherwise read as ZERO.
	call_deferred("_emit_fixture")


func _emit_fixture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("usage: placements_contract.gd -- <output.json>")
		quit(2)
		return

	var terrain := TerrainGrid.new()
	terrain.min_height = 4000.0
	terrain.vis_surface_scale = 2.0
	terrain.vis_height_scale = 10.0
	root.add_child(terrain)

	var tool := PlacementTool.new()
	root.add_child(tool)
	tool.restore(
		"ContractRock",
		"ContractPlacement",
		Vector3(25.0, 32.0, -16.2),
		Vector3(0.25, PI / 2.0, -0.5),
		1.5)
	tool.restore(
		"ContractRock",
		"",
		Vector3(4.0, 0.0, 6.0),
		Vector3.ZERO,
		1.0)

	var output_path: String = args[0]
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		push_error("cannot write placements contract fixture: " + output_path)
		quit(3)
		return
	output.store_string(PlacementsIo._serialize(tool, terrain))
	output.close()
	print("wrote producer placements fixture: " + output_path)
	quit()
