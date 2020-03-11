tool
class_name ConceptGraphTemplate
extends GraphEdit

"""
Load and edit graph templates. The internal graph is then stored back in the template file.
"""


signal graph_changed
signal simulation_outdated
signal connection_changed

var concept_graph
var root: Spatial
var node_library: ConceptNodeLibrary

var _output_node: ConceptNode
var _selected_node: GraphNode
var _template_loaded := false


func _init() -> void:
	_setup_gui()
	ConceptGraphDataType.setup_valid_connection_types(self)
	connect("connection_request", self, "_on_connection_request")
	connect("disconnection_request", self, "_on_disconnection_request")
	connect("node_selected", self, "_on_node_selected")
	connect("_end_node_move", self, "_on_node_changed")


"""
Remove all children and connections
"""
func clear() -> void:
	_template_loaded = false
	clear_connections()
	for c in get_children():
		if c is GraphNode:
			remove_child(c)
			c.queue_free()


"""
Creates a node using the provided model and add it as child which makes it visible and editable
from the Concept Graph Editor
"""
func create_node(node: ConceptNode, data := {}, notify := true) -> ConceptNode:
	if _output_node and node.node_title == "Output":
		return null # Only one output node per template

	var new_node: ConceptNode = node.duplicate()
	new_node.offset = scroll_offset + Vector2(250, 150)

	_connect_node_signals(new_node)
	add_child(new_node)

	if data.has("name"):
		new_node.name = data["name"]
	if data.has("editor"):
		new_node.restore_editor_data(data["editor"])
	if data.has("data"):
		new_node.restore_custom_data(data["data"])

	if notify:
		emit_signal("graph_changed")
		emit_signal("simulation_outdated")

	return new_node


func delete_node(node) -> void:
	if node.node_title == "Output":
		return
	_disconnect_node_signals(node)
	_disconnect_active_connections(node)
	remove_child(node)
	node.queue_free()
	emit_signal("graph_changed")
	emit_signal("simulation_outdated")
	update() # Force the GraphEdit to redraw to hide the old connections to the deleted node


"""
Add custom properties in the ConceptGraph inspector panel to expose variables at the instance level.
This is used to change parameters on an instance without having to modify the template itself
(And thus modifying all the other ConceptGraph using the same template).
"""
func update_exposed_variables() -> void:
	var exposed_variables = []
	for c in get_children():
		if c is ConceptNode:
			var variables = c.get_exposed_variables()
			for v in variables:
				v.name = "Template/" + v.name
				v.type = ConceptGraphDataType.to_variant_type(v.type)
				exposed_variables.append(v)

	concept_graph.update_exposed_variables(exposed_variables)


"""
Get exposed variable from the inspector
"""
func get_value_from_inspector(name: String):
	return concept_graph.get("Template/" + name)


"""
Clears the cache of every single node in the template. Useful when only the inputs changes
and node the whole graph structure itself. Next time get_output is called, every nodes will
recalculate their output
"""
func clear_simulation_cache() -> void:
	for node in get_children():
		if node is ConceptNode:
			node.clear_cache()


"""
Returns the final result generated by the whole graph
"""
func get_output() -> Spatial:
	if not _output_node:
		if _template_loaded:
			print("Error : No output node found in ", get_parent().get_name())
		return null
	return _output_node.get_output(0)


"""
Returns a dictionnary containing the ConceptNode and the slot index the connection originates from
"""
func get_left_node(node: ConceptNode, slot: int) -> Dictionary:
	var result = {}
	for c in get_connection_list():
		if c["to"] == node.get_name() and c["to_port"] == slot:
			result["node"] = get_node(c["from"])
			result["slot"] = c["from_port"]
			return result
	return result


"""
Returns an array of ConceptNodes connected to the right of the given slot.
"""
func get_right_nodes(node: ConceptNode, slot: int) -> Array:
	var result = []
	for c in get_connection_list():
		if c["from"] == node.get_name() and c["from_port"] == slot:
			result.append(get_node(c["to"]))
	return result


"""
Returns an array of all the ConceptNodes on the right, regardless of the slot.
"""
func get_all_right_nodes(node) -> Array:
	var result = []
	for c in get_connection_list():
		if c["from"] == node.get_name():
			result.append(get_node(c["to"]))
	return result


func is_node_connected_to_input(node: GraphNode, idx: int) -> bool:
	var name = node.get_name()
	for c in get_connection_list():
		if c["to"] == name and c["to_port"] == idx:
			return true
	return false


func load_from_file(path: String) -> void:
	if not node_library or not path or path == "":
		return

	clear()

	var file = File.new()
	file.open(path, File.READ)
	var json = JSON.parse(file.get_line())
	if not json:
		return	# Template file is either empty or not a valid Json. Ignore

	var graph: Dictionary = json.result
	if not graph.has("nodes"):
		return

	var node_list = node_library.get_list()
	for node_data in graph["nodes"]:
		if not node_data.has("type"):
			continue

		var type = node_data["type"]
		if not node_list.has(type):
			print("Error: Node type ", type, " could not be found. Aborting template loading.")
			clear()
			return

		var node_instance = node_list[type]
		var node = create_node(node_instance, node_data, false)

		if node.node_title == "Output":
			_output_node = node

	for c in graph["connections"]:
		connect_node(c["from"], c["from_port"], c["to"], c["to_port"])
		get_node(c["to"]).emit_signal("connection_changed")

	_template_loaded = true


func save_to_file(path: String) -> void:
	var graph := {}
	graph["connections"] = get_connection_list()
	graph["nodes"] = []

	for c in get_children():
		if c is ConceptNode:
			var node = {}
			node["name"] = c.get_name()
			node["type"] = c.node_title
			node["editor"] = c.export_editor_data()
			node["data"] = c.export_custom_data()
			graph["nodes"].append(node)

	var file = File.new()
	file.open(path, File.WRITE)
	file.store_line(to_json(graph))
	file.close()


func _setup_gui() -> void:
	right_disconnects = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	anchor_right = 1.0
	anchor_bottom = 1.0


func _connect_node_signals(node) -> void:
	node.connect("node_changed", self, "_on_node_changed")
	node.connect("delete_node", self, "delete_node")


func _disconnect_node_signals(node) -> void:
	node.disconnect("node_changed", self, "_on_node_changed")
	node.disconnect("delete_node", self, "delete_node")


func _disconnect_active_connections(node: GraphNode) -> void:
	var name = node.get_name()
	for c in get_connection_list():
		if c["to"] == name or c["from"] == name:
			disconnect_node(c["from"], c["from_port"], c["to"], c["to_port"])


func _disconnect_input(node: GraphNode, idx: int) -> void:
	var name = node.get_name()
	for c in get_connection_list():
		if c["to"] == name and c["to_port"] == idx:
			disconnect_node(c["from"], c["from_port"], c["to"], c["to_port"])
			return


func _on_node_selected(node: GraphNode) -> void:
	_selected_node = node


func _on_node_changed(node: ConceptNode = null, replay_simulation := false) -> void:
	emit_signal("graph_changed")
	if replay_simulation:
		emit_signal("simulation_outdated")


func _on_connection_request(from_node: String, from_slot: int, to_node: String, to_slot: int) -> void:
	# Prevent connecting the node to itself
	if from_node == to_node:
		return

	# Disconnect any existing connection to the input slot first
	for c in get_connection_list():
		if c["to"] == to_node and c["to_port"] == to_slot:
			disconnect_node(c["from"], c["from_port"], c["to"], c["to_port"])
			break

	connect_node(from_node, from_slot, to_node, to_slot)
	emit_signal("graph_changed")
	emit_signal("simulation_outdated")
	get_node(to_node).emit_signal("connection_changed")


func _on_disconnection_request(from_node: String, from_slot: int, to_node: String, to_slot: int) -> void:
	disconnect_node(from_node, from_slot, to_node, to_slot)
	emit_signal("graph_changed")
	emit_signal("simulation_outdated")
	get_node(to_node).emit_signal("connection_changed")
