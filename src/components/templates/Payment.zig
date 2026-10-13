// const std = @import("std");
// const Vapor = @import("vapor");
// const Text = Vapor.Text;
// const Box = Vapor.Box;
// const Center = Vapor.Center;
// const Stack = Vapor.Stack;
// const Opaque = @import("../Opaque.zig");
// const Tabs = Opaque.Tabs;
// const Field = Opaque.Field;
// const Button = Opaque.Button;
// const glitch = Opaque.glitch;
// const KeyStone = Vapor.KeyStone;
// const TrainTicket = @import("TrainTicket.zig");
// const utils = Vapor.utils;
// const Compiler = @import("../../main.zig");
// const Vaporize = @import("vaporize");
// const Validation = @import("vaporize").Validation;
// const ValidationError = @import("vaporize").ValidationError;
// const Select = @import("../Select.zig").Select;
//
// const Payment = @This();
// title: []const u8 = "Payment",
// subtitle: []const u8 = "Payment to your account",
// currency_dropdown: Select(Currency) = undefined,
// details: Details = .{},
//
// var hovered: ?*const Vapor.IconTokens = null;
//
// const Currency = enum { usd, eur };
//
// pub const Details = struct {
//     amount: f32 = 49.99,
//     currency: Currency = .usd,
// };
//
// pub fn init(payment: *Payment) void {
//     payment.currency_dropdown = .fromItems(&.{
//         Select(Currency).Item{ .value = Currency.usd, .label = "USD" },
//         Select(Currency).Item{ .value = Currency.eur, .label = "EUR" },
//     });
//     payment.currency_dropdown.on_select = onCurrencySelect;
//     payment.currency_dropdown.default(Select(Currency).Item{ .value = Currency.usd, .label = "USD" });
//     payment.currency_dropdown.trigger = "Currency";
// }
//
// fn onCurrencySelect(select: *Select(Currency), item: *Select(Currency).Item) void {
//     const payment: *Payment = @fieldParentPtr("currency_dropdown", select);
//     payment.details.currency = item.value;
// }
//
// fn onHover(icon: *const Vapor.IconTokens, _: *Vapor.Event) void {
//     hovered = icon;
// }
//
// fn onLeave(_: *Vapor.Event) void {
//     hovered = null;
// }
//
// fn callPayment(payment: *Payment) void {
//     Vapor.print("Calling payment {any}", .{payment.details});
//     Vapor.Kit.fetch("http://localhost:8080/checkout", handlePayment, .{
//         .method = .POST,
//         .credentials = "include",
//         .headers = .{
//             .content_type = "application/x-www-form-urlencoded",
//         },
//         .body = Vapor.fmtln("amount={d}&currency={s}", .{ payment.details.amount * 100, @tagName(payment.details.currency) }),
//     });
// }
//
// fn handlePayment(resp: Vapor.Kit.Response) void {
//     switch (resp) {
//         .ok => |data| {
//             Vapor.Kit.setWindowLocation(data.body);
//         },
//         .err => |err| {
//             Vapor.println("Failed to fetch payment data: {s}", .{err.message});
//         },
//     }
// }
//
// fn onChange(evt: *Vapor.Event) void {
//     evt.preventDefault();
//     Vapor.print("onChange {s}", .{evt.text()});
// }
//
// fn Card() Vapor.Builder(.pure) {
//     return Stack()
//         .background(.transparentizeHex(.palette(.background), 0.5))
//         .border(.round(.palette(.border_color_light), .all(12)))
//         .width(.percent(100))
//         .padding(.all(16))
//         .layout(.top_left)
//         .spacing(16);
// }
//
// pub fn render(payment: *Payment) void {
//     const active_index = Tabs.NavBar("payment_options", &.{"Payment"});
//     switch (active_index) {
//         0 => {
//             Card().children({
//                 Stack()
//                     .width(.percent(100))
//                     .spacing(8)
//                     .children({
//                     Text(payment.title)
//                         .font(16, 700, .palette(.text_color))
//                         .end();
//                     Text(payment.subtitle)
//                         .font(14, 300, .palette(.text_color))
//                         .end();
//                 });
//                 Stack()
//                     .width(.percent(100))
//                     .spacing(16)
//                     .children({
//                     Field.render(.{
//                         .label = "Amount",
//                         .value = .{ .float = &payment.details.amount },
//                         .type = .float,
//                         .id = "amount",
//                     });
//                     payment.currency_dropdown.render();
//                 });
//                 Box()
//                     .width(.percent(100))
//                     .spacing(16)
//                     .layout(.left_center)
//                     .children({
//                     Button(callPayment, .{payment})
//                         .size(.hw(.px(36), .percent(100)))
//                         .layout(.center)
//                         .background(.transparentizeHex(.black, 0.8))
//                         .border(.round(.black, .all(8)))
//                         .pointer()
//                         .hover(.{
//                             .background = .yellow,
//                             .text_color = .black,
//                         })
//                         .onEventCtx(.pointerenter, onHover, Vapor.IconTokens.stripe)
//                         .onLeave(onLeave)
//                         .children({
//                         const active = hovered != null and std.mem.eql(u8, hovered.?.web.?, Vapor.IconTokens.stripe.web.?);
//                         Text("Submit Payment")
//                             .fontFamily("IBM Plex Sans,monospace")
//                             .font(16, 300, if (active) .black else .palette(.alternate_text_color)).end();
//                     });
//                 });
//             });
//         },
//         else => {},
//     }
// }

const std = @import("std");
const Vapor = @import("vapor");
const Text = Vapor.Text;
const Box = Vapor.Box;
const Center = Vapor.Center;
const Stack = Vapor.Stack;
const Opaque = @import("../Opaque.zig");
const Button = Opaque.Button;
const glitch = Opaque.glitch;

const PricingCards = @This();

pub const Tier = enum {
    free,
    pro,
    premium,
};

pub const PricingPlan = struct {
    tier: Tier,
    name: []const u8,
    price: []const u8,
    period: []const u8,
    description: []const u8,
    features: []const []const u8,
    cta_text: []const u8,
    highlighted: bool = false,
};

var hovered_tier: ?Tier = null;

const plans = [_]PricingPlan{
    .{
        .tier = .free,
        .name = "Free",
        .price = "$0",
        .period = "/month",
        .description = "Perfect for testing and experimentation",
        .features = &.{
            "Up to 3 projects",
            "Full Tether Integration",
            "Community support",
            "Basic analytics",
            "Database Interface",
            "Postman like API",
            "API access (100 req/day)",
        },
        .cta_text = "Get Started",
        .highlighted = false,
    },
    .{
        .tier = .pro,
        .name = "Pro",
        .price = "$29",
        .period = "/month",
        .description = "For professionals and growing teams",
        .features = &.{
            "Unlimited projects",
            "Full Tether Integration",
            "100GB storage",
            "Priority support",
            "Advanced analytics",
            "Advanced Feature Set",
            "API access (unlimited)",
            "Team collaboration",
        },
        .cta_text = "Start Free Trial",
        .highlighted = true,
    },
    .{
        .tier = .premium,
        .name = "Premium",
        .price = "79",
        .period = "/month",
        .description = "For large organizations with custom needs",
        .features = &.{
            "Everything in Pro",
            "Unlimited storage",
            "24/7 dedicated support",
            "Audit logs",
            "On-premise option",
            "Deployment options",
            "Team collaboration",
            "Full Feature Set",
        },
        .cta_text = "Go Premium",
        .highlighted = false,
    },
};

fn onHoverTier(tier: Tier, _: *Vapor.Event) void {
    hovered_tier = tier;
}

fn onLeaveTier(_: *Vapor.Event) void {
    hovered_tier = null;
}

fn onSelectPlan(tier: Tier) void {
    Vapor.print("Selected plan: {s}", .{@tagName(tier)});
}

fn PricingCard(plan: *const PricingPlan) void {
    // const is_hovered = hovered_tier != null and hovered_tier.? == plan.tier;
    const is_highlighted = plan.highlighted;

    const text_color: Vapor.Types.Color = if (is_highlighted) .palette(.alternate_text_color) else .palette(.text_color);

    Stack()
        .width(.px(320))
        .height(.fit)
        .padding(.all(24))
        .spacing(20)
        .layout(.top_left)
        .background(if (is_highlighted)
            .transparentizeHex(.palette(.tint), 0.6)
        else
            .transparentizeHex(.palette(.background), 0.5))
        .border(.sharp(
            .all(1),
            if (is_highlighted) .palette(.tint) else .palette(.border_color_light),
        ))
        .duration(200)
        .hover(.{
            .transform = .translate(0, -8, .px),
            .border = .round(if (is_highlighted) .palette(.tint) else .palette(.border_color_light), .all(16)),
            .new_shadow = Vapor.Types.NewShadow.init()
                .inset(0, -2, .transparentizeHex(.black, 0.3))
                .drop(0, 1, 3, .transparentizeHex(.black, 0.1)),
        })
        .onEventCtx(.pointerenter, onHoverTier, .{plan.tier})
        .onLeave(onLeaveTier)
        .children({
        // Badge for highlighted plan
        if (is_highlighted) {
            Box()
                .width(.percent(100))
                .layout(.center)
                .children({
                Box()
                    .padding(.tblr(6, 6, 12, 12))
                    .background(.palette(.tint))
                    .border(.round(.palette(.tint), .all(99)))
                    .children({
                    Text("Most Popular")
                        .font(12, 600, .palette(.alternate_text_color))
                        .fontFamily("IBM Plex Sans,monospace")
                        .end();
                });
            });
        }

        // Plan name
        Text(plan.name)
            .font(24, 700, text_color)
            .fontFamily("Montserrat")
            .end();

        // Price
        Box()
            .layout(.bottom_left)
            .spacing(4)
            .children({
            Text(plan.price)
                .font(48, 700, text_color)
                .fontFamily("Montserrat")
                .end();
            if (plan.period.len > 0) {
                Text(plan.period)
                    .font(16, 300, text_color)
                    .fontFamily("IBM Plex Sans,monospace")
                    .end();
            }
        });

        // Description
        Text(plan.description)
            .font(14, 300, text_color)
            .fontFamily("IBM Plex Sans,monospace")
            .end();

        // Divider
        Box()
            .width(.percent(100))
            .height(.px(1))
            .background(.palette(.border_color_light))
            .children({});

        // Features list
        Stack()
            .width(.percent(100))
            .spacing(12)
            .children({
            for (plan.features) |feature| {
                Box()
                    .width(.percent(100))
                    .layout(.left_center)
                    .spacing(10)
                    .children({
                    Vapor.Icon(.check)
                        .font(16, 700, if (is_highlighted) .palette(.tint) else .palette(.text_color))
                        .end();
                    Text(feature)
                        .font(14, 300, text_color)
                        .fontFamily("IBM Plex Sans,monospace")
                        .end();
                });
            }
        });

        // CTA Button
        Box()
            .width(.percent(100))
            .padding(.tb(16, 0))
            .layout(.center)
            .children({
            Button(onSelectPlan, .{plan.tier})
                .size(.hw(.px(42), .percent(80)))
                .layout(.center)
                .background(if (is_highlighted)
                    .palette(.tint)
                else
                    .transparent)
                .border(.round(
                    if (is_highlighted) .palette(.tint) else .palette(.text_color),
                    .all(12),
                ))
                .pointer()
                .duration(150)
                .hover(.{
                    // .background = if (is_highlighted) .transparentizeHex(.palette(.tint), 0.2) else .palette(.text_color),
                    // .text_color = .palette(.background),
                    .transform = .scaleDecimal(1.02),
                })
                .font(16, 500, text_color)
                .children({
                Text(plan.cta_text)
                    .fontFamily("IBM Plex Sans,monospace")
                    .font(16, 500, null)
                    .end();
            });
        });
    });
}

pub fn render() void {
    Stack()
        .width(.percent(100))
        .layout(.center)
        .spacing(32)
        .padding(.all(48))
        .children({
        // Header section
        Stack()
            .layout(.center)
            .spacing(12)
            .children({
            Text("Acorn Pricing")
                .font(42, 700, .palette(.text_color))
                .fontFamily("Montserrat")
                .end();
            Text("Replace Sentry, Supabase, Postman, and more with Acorn. Choose the plan that fits your needs. Upgrade or downgrade at any time.")
                .font(16, 300, .palette(.text_color))
                .fontFamily("IBM Plex Sans,monospace")
                .end();
        });

        // Pricing cards row
        Box()
            .width(.percent(100))
            .layout(.center)
            .spacing(24)
            .children({
            inline for (&plans) |*plan| {
                PricingCard(plan);
            }
        });

        // Footer note
        Stack()
            .layout(.center)
            .spacing(8)
            .children({
            Text("Free plan includes 14-day free trial · No credit card required")
                .font(14, 300, .palette(.text_color))
                .fontFamily("IBM Plex Sans,monospace")
                .end();
            Box()
                .layout(.center)
                .spacing(16)
                .children({
                Button(Vapor.print, .{ "Acorn Pricing clicked", .{} })
                    .children({
                    Text("See what people are saying →")
                        .font(14, 500, .palette(.tint))
                        .fontFamily("IBM Plex Sans,monospace")
                        .end();
                });
            });
        });
    });
}

pub fn init() void {
    // Initialize any required state
}
