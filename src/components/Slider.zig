const std = @import("std");
const Vapor = @import("vapor");
const Box = Vapor.Box;
const Draggable = Vapor.Draggable;

var points: std.StringHashMap(*Point) = undefined;
var binded_comps: std.StringHashMap(*Vapor.Binded) = undefined;

pub fn new() void {
    points = std.StringHashMap(*Point).init(Vapor.arena(.persist));
    binded_comps = std.StringHashMap(*Vapor.Binded).init(Vapor.arena(.persist));
}

const Point = struct {
    x: f32 = 0,
    draggable: Draggable,
    binded: *Vapor.Binded = undefined,
    binded_trans: *Vapor.Binded = undefined,
};

const Slider = @This();
max: f32 = 100,
min: f32 = 0,
value: f32 = 0,
step: f32 = 1,

fn onMove(draggable: *Draggable, evt: *Vapor.Event) void {
    evt.preventDefault();
    const point: *Point = @fieldParentPtr("draggable", draggable);
    const bounds = point.binded.getBoundingClientRect() orelse return;
    const bounds_width = bounds.width - 18;

    const delta = draggable.movement_x;
    point.x += delta;
    if (point.x <= 0) {
        point.x = 0;
    } else if (point.x >= bounds_width) {
        point.x = bounds_width;
    }
    draggable.updatePosition(point.x, 0);
    point.binded_trans.mutateStyleString("width", Vapor.fmtln("{d}px", .{point.x + 9}));
}

fn DragBox() Vapor.Builder(.pure) {
    return Box()
        .pos(.tl(.px(-6), .px(0), .absolute))
        .width(.px(18))
        .height(.px(18))
        .border(.round(.palette(.alternate_background), .all(99)))
        .background(.white);
}

fn Slide() Vapor.Builder(.pure) {
    return Box()
        .pos(.absolute)
        .height(.px(6))
        .border(.round(.transparent, .all(99)))
        .background(.palette(.border_color_light));
}

fn mount(point: *Point) void {
    const bound = point.binded.getBoundingClientRect() orelse return;
    const bounds_width = bound.width / 2;
    point.x = bounds_width;
    point.binded_trans.mutateStyleString("width", Vapor.fmtln("{d}px", .{bounds_width + 9}));
    point.draggable.updatePosition(bounds_width, 0);
}

pub fn render(_: Slider) void {
    Box()
        .pos(.relative)
        .direction(.column)
        .children({

        // Hello
        var slide = Slide();
        const slide_uuid = slide.getUUID();

        const binded = binded_comps.get(slide_uuid) orelse blk: {
            const binded = Vapor.arena(.persist).create(Vapor.Binded) catch unreachable;
            binded.* = .{};
            binded_comps.put(slide_uuid, binded) catch unreachable;
            break :blk binded;
        };

        slide
            .width(.percent(100))
            .ref(binded)
            .children({});

        var slide_trans = Slide();
        const slide_trans_uuid = slide_trans.getUUID();

        const binded_trans = binded_comps.get(slide_trans_uuid) orelse blk: {
            const binded_trans = Vapor.arena(.persist).create(Vapor.Binded) catch unreachable;
            binded_trans.* = .{};
            binded_comps.put(slide_trans_uuid, binded_trans) catch unreachable;
            break :blk binded_trans;
        };

        slide_trans
            .width(.percent(0))
            .background(.palette(.text_color))
            .ref(binded_trans)
            .children({});

        var drag_box = DragBox();

        const uuid = drag_box.getUUID();


        const point = points.get(uuid) orelse blk: {
            const draggable = Vapor.arena(.persist).create(Draggable) catch unreachable;
            draggable.* = .{
                .on_drag = onMove,
            };
            const point = Vapor.arena(.persist).create(Point) catch unreachable;
            point.* = .{
                .draggable = draggable.*,
                .binded = binded,
                .binded_trans = binded_trans,
            };
            points.put(uuid, point) catch unreachable;
            break :blk point;
        };

        drag_box
            .id("draggable")
            .createDraggable(&point.draggable)
            .onMount(mount, .{point})
            .children({});
    });
}
