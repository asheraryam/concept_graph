class_name ConceptBoxInput
extends MeshInstance


signal input_changed
signal property_changed


var size := Vector3.ONE setget set_size
var auto_center := false setget set_auto_center # TODO: implement standard AABB behavior
var center := Vector3.ZERO setget set_center


func _ready() -> void:
	add_user_signal('input_changed')
	set_notify_local_transform(true)


func _notification(type: int):
	if type == NOTIFICATION_TRANSFORM_CHANGED:
		_on_box_changed()


func is_inside(pos: Vector3, ignore_y_axis: bool = false) -> bool:
	var t = transform
	if is_inside_tree():
		t = global_transform
	var local = t.xform_inv(pos)
	if ignore_y_axis:
		local.y = size.y / 3.0
	var aabb = AABB(center - (size / 2.0), size)
	return aabb.has_point(local)


func set_size(val: Vector3) -> void:
	size = val
	_on_box_changed()


func set_auto_center(val: bool) -> void:
	auto_center = val


func set_center(val: Vector3) -> void:
	center = val
	_on_box_changed()


func _on_box_changed() -> void:
	emit_signal("input_changed", self)	# That tell the ConceptGraph to rerun the simulation
