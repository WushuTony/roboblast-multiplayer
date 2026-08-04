@tool
extends ItemList
class_name AutowrapItemList

## If set to something other than [constant TextServer.AUTOWRAP_OFF], the text gets wrapped inside
## each item of the item list, allowing to display one item on multiple lines.
@export var autowrap_mode: TextServer.AutowrapMode = TextServer.AUTOWRAP_ARBITRARY:
	set(value):
		autowrap_mode = value
		if Engine.is_editor_hint():
			update_configuration_warnings()
## If enabled, when items are added while the vertical scrollbar is at the bottom, automatically
## scroll to stay at the bottom and always display the newest item.[br]
@export var autoscroll_bottom: bool = false
## The maximum number of items that can be added to the list.[br]
## [b]Note:[/b] An item wrapped on multiple lines count as multiple items.
@export var max_item_count: int = -1
## If [param max_item_count] is set and the limit is reached, trigger the custom behaviour when a new
## item is added to the list.
@export var max_item_count_behaviour: CustomAddItemBehaviour = CustomAddItemBehaviour.DISCARD_OLDEST_ITEM

enum CustomAddItemBehaviour
{
	## Removes the oldest item from the list, or items if they share the same [code]group_id[/code].
	DISCARD_OLDEST_ITEM,
	## Prevents adding any new item to the list.
	REJECT_NEW_ITEM
}

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if autowrap_mode == TextServer.AUTOWRAP_OFF:
		warnings.append("Autowrap Mode is disabled, consider using an ItemList instead.")
	
	return warnings

## Adds items to the item list with specified text wrapped. Returns the indexes of the added items.[br][br]
## Specify an [param icon], or use [code]null[/code] as the [param icon] for items with no icon.[br][br]
## If [param selectable] is [code]true[/code], the items will be selectable.
func add_wrapped_items(text: String, icon: Texture2D = null, selectable: bool = true) -> Array[int]:
	var item_indexes: Array[int] = []
	if max_item_count >= 0 and item_count >= max_item_count:
		match (max_item_count_behaviour):
			CustomAddItemBehaviour.DISCARD_OLDEST_ITEM:
				while (item_count >= max_item_count):
					remove_wrapped_items(0)
			CustomAddItemBehaviour.REJECT_NEW_ITEM:
				return item_indexes
	
	var vscrollbar: VScrollBar = get_v_scroll_bar()
	var scrollbar_at_bottom: bool = (vscrollbar.value >= vscrollbar.max_value - vscrollbar.page - 1.0)
	var scrollbar_visible: bool = vscrollbar.visible
	
	if autowrap_mode == TextServer.AUTOWRAP_OFF:
		item_indexes.append(add_item(text, icon, selectable))
		if autoscroll_bottom and (scrollbar_at_bottom or scrollbar_visible != vscrollbar.visible):
			_scroll_to_bottom.call_deferred()
		return item_indexes
	
	var paragraph: TextParagraph = TextParagraph.new()
	paragraph.direction = TextServer.DIRECTION_LTR
	paragraph.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Substract the scrollbar's offset from the non-fixed size so the text isn't hidden by the scrollbar
	var scrollbar_offset: float = vscrollbar.size.x - vscrollbar.offset_right
	paragraph.width = fixed_column_width if fixed_column_width > 0 else int(size.x - scrollbar_offset)
	
	match autowrap_mode:
		TextServer.AUTOWRAP_OFF:
			paragraph.break_flags = TextServer.BREAK_MANDATORY
		TextServer.AUTOWRAP_ARBITRARY:
			paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_GRAPHEME_BOUND
		TextServer.AUTOWRAP_WORD:
			paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
		TextServer.AUTOWRAP_WORD_SMART:
			paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	
	var current_font: Font = get_theme_font("font")
	var current_font_size: int = get_theme_font_size("font_size")
	paragraph.add_string(text, current_font, current_font_size)
	
	var line_count: int = paragraph.get_line_count()
	if line_count < 2:
		item_indexes.append(add_item(text, icon, selectable))
		if autoscroll_bottom and (scrollbar_at_bottom or scrollbar_visible != vscrollbar.visible):
			_scroll_to_bottom.call_deferred()
		return item_indexes
	
	# Generate a unique ID for this block so we know these lines belong together
	var paragraph_group_id: int = Time.get_ticks_msec() + randi()
	
	# Add each line as a distinct item to the list
	for i in range(line_count):
		var line_range: Vector2i = paragraph.get_line_range(i)
		var line_string: String = text.substr(line_range.x, line_range.y - line_range.x)
		
		# Only pass the icon/selectable to the very first line of the block
		var current_icon: Texture2D = icon if i == 0 else null
		var current_selectable: bool = selectable and i == 0
		
		var current_index = add_item(line_string, current_icon, current_selectable)
		
		# Bind the lines together using metadata
		set_item_metadata(current_index, {
			"group_id": paragraph_group_id,
			"is_root": (i == 0),
			"full_text": text
		})
		
		item_indexes.append(current_index)
	
	# If the max item count was exceeded, then remove items to stay within the limit
	if max_item_count >= 0 and item_count > max_item_count:
		match (max_item_count_behaviour):
			CustomAddItemBehaviour.DISCARD_OLDEST_ITEM:
				while (item_count > max_item_count):
					remove_wrapped_items(0)
			CustomAddItemBehaviour.REJECT_NEW_ITEM:
				remove_wrapped_items(item_indexes[0])
				item_indexes.clear()
	
	if autoscroll_bottom and (scrollbar_at_bottom or scrollbar_visible != vscrollbar.visible) and item_indexes.size() > 0:
		_scroll_to_bottom.call_deferred()
	
	return item_indexes

## Removes the item specified by [param idx] index from the list, or items if adjacent items share
## the same [code]group_id[/code].
func remove_wrapped_items(idx: int) -> void:
	var item_metadata: Variant = get_item_metadata(idx)
	if item_metadata == null:
		remove_item(idx)
		return
	
	var group_id_to_remove: int = item_metadata.group_id
	
	# Making sure we start removing the items from the root
	while idx > 0 and not item_metadata.is_root:
		var prev_item_metadata: Variant = get_item_metadata(idx - 1)
		if (prev_item_metadata == null or
			prev_item_metadata.group_id != group_id_to_remove):
			break
		
		idx -= 1
		item_metadata = prev_item_metadata
	
	# Remove all the items with the same group_id
	while item_metadata.group_id == group_id_to_remove:
		remove_item(idx)
		item_metadata = get_item_metadata(idx)
		if item_metadata == null:
			break

func _scroll_to_bottom() -> void:
	var vscrollbar: VScrollBar = get_v_scroll_bar()
	vscrollbar.set_value(vscrollbar.max_value)
