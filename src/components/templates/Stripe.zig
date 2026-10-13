const std = @import("std");
const Vapor = @import("vapor");
const Text = Vapor.Text;
const Box = Vapor.Box;
const Center = Vapor.Center;
const Stack = Vapor.Stack;
const Opaque = @import("../Opaque.zig");
const Tabs = Opaque.Tabs;
const Field = Opaque.Field;
const Button = Opaque.Button;
const glitch = Opaque.glitch;
const KeyStone = Vapor.KeyStone;
const TrainTicket = @import("TrainTicket.zig");
const utils = Vapor.utils;
const Compiler = @import("../../main.zig");
const Vaporize = @import("vaporize");
const Validation = @import("vaporize").Validation;
const ValidationError = @import("vaporize").ValidationError;
const Select = @import("../Select.zig").Select;

const Payment = @This();
title: []const u8 = "Payment",
subtitle: []const u8 = "Payment to your account",
currency_dropdown: Select(Currency) = undefined,
details: Details = .{},

var hovered: ?*const Vapor.IconTokens = null;

const Currency = enum { usd, eur };

pub const Details = struct {
    amount: f32 = 49.99,
    currency: Currency = .usd,
};

pub fn init(payment: *Payment) void {
    payment.currency_dropdown = .fromItems(&.{
        Select(Currency).Item{ .value = Currency.usd, .label = "USD" },
        Select(Currency).Item{ .value = Currency.eur, .label = "EUR" },
    });
    payment.currency_dropdown.on_select = onCurrencySelect;
    payment.currency_dropdown.default(Select(Currency).Item{ .value = Currency.usd, .label = "USD" });
    payment.currency_dropdown.trigger = "Currency";
}

fn onCurrencySelect(select: *Select(Currency), item: *Select(Currency).Item) void {
    const payment: *Payment = @fieldParentPtr("currency_dropdown", select);
    payment.details.currency = item.value;
}

fn onHover(icon: *const Vapor.IconTokens, _: *Vapor.Event) void {
    hovered = icon;
}

fn onLeave(_: *Vapor.Event) void {
    hovered = null;
}

fn callPayment(payment: *Payment) void {
    Vapor.print("Calling payment {any}", .{payment.details});
    Vapor.Kit.fetch("http://localhost:8080/checkout", handlePayment, .{
        .method = .POST,
        .credentials = "include",
        .headers = .{
            .content_type = "application/x-www-form-urlencoded",
        },
        .body = Vapor.fmtln("amount={d}&currency={s}", .{ payment.details.amount * 100, @tagName(payment.details.currency) }),
    });
}

fn handlePayment(resp: Vapor.Kit.Response) void {
    switch (resp) {
        .Ok => |data| {
            Vapor.Kit.setWindowLocation(data.body);
        },
        .Err => |err| {
            Vapor.println("Failed to fetch payment data: {s}", .{err.message});
        },
    }
}

fn onChange(evt: *Vapor.Event) void {
    evt.preventDefault();
    Vapor.print("onChange {s}", .{evt.text()});
}

fn Card() Vapor.Builder(.pure) {
    return Stack()
        .background(.transparentizeHex(.palette(.background), 0.5))
        .border(.round(.palette(.border_color_light), .all(12)))
        .width(.percent(100))
        .padding(.all(16))
        .layout(.top_left)
        .spacing(16);
}

pub fn render(payment: *Payment) void {
    Card().children({
        Stack()
            .width(.percent(100))
            .spacing(8)
            .children({
            Text(payment.title)
                .font(16, 700, .palette(.text_color))
                .end();
            Text(payment.subtitle)
                .font(14, 300, .palette(.text_color))
                .end();
        });
        Stack()
            .width(.percent(100))
            .spacing(16)
            .children({
            Field.render(.{
                .label = "Amount",
                .value = .{ .float = &payment.details.amount },
                .type = .float,
                .id = "amount",
            });
            payment.currency_dropdown.render();
        });
        Box()
            .width(.percent(100))
            .spacing(16)
            .layout(.left_center)
            .children({
            Button(callPayment, .{payment})
                .size(.hw(.px(36), .percent(100)))
                .layout(.center)
                .background(.transparentizeHex(.black, 0.8))
                .border(.round(.black, .all(8)))
                .pointer()
                .hover(.{
                    .background = .yellow,
                    .text_color = .black,
                })
                .onEventCtx(.pointerenter, onHover, .{Vapor.IconTokens.stripe})
                .onLeave(onLeave)
                .children({
                const active = hovered != null and std.mem.eql(u8, hovered.?.web.?, Vapor.IconTokens.stripe.web.?);
                Text("Submit Payment")
                    .fontFamily("IBM Plex Sans,monospace")
                    .font(16, 300, if (active) .black else .palette(.alternate_text_color)).end();
            });
        });
    });
}
