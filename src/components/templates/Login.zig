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
const KeyStone = @import("keystone");
const TrainTicket = @import("TrainTicket.zig");
const utils = Vapor.utils;
const Compiler = @import("../../main.zig");
const Vaporize = @import("vaporize");
const Validation = @import("vaporize").Validation;
const ValidationError = @import("vaporize").ValidationError;
const Select = @import("../Select.zig").Select;

const Login = @This();
login_title: []const u8 = "Login",
login_subtitle: []const u8 = "Login to your account",
create_account_title: []const u8 = "Create Account",
create_account_subtitle: []const u8 = "Create an account to login",

var hovered: ?*const Vapor.IconTokens = null;

pub const Details = struct {
    email: []const u8 = "",
    password: []const u8 = "",
};

var details: Details = .{};

const key =
    \\<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-key-icon lucide-key"><path d="m15.5 7.5 2.3 2.3a1 1 0 0 0 1.4 0l2.1-2.1a1 1 0 0 0 0-1.4L19 4"/><path d="m21 2-9.6 9.6"/><circle cx="7.5" cy="15.5" r="5.5"/></svg>
;

fn submit() void {
    if (KeyStone.isAuthenticated()) {
        Vapor.print("Already logged in", .{});
    } else {
        Vapor.print("Logging in", .{});
    }
}

fn createAccount() void {
    const payload = utils.stringify(details, .frame) catch unreachable;
    Vapor.Kit.fetch("http://localhost:8080/user", createdAccount, .{
        .method = .POST,
        .credentials = "include",
        .body = payload,
        .body_type = .json,
    });
}

fn createdAccount(resp: Vapor.Fetch.Result) void {
    if (resp.isOk()) {
        Vapor.println("Account created {s}", .{resp.Ok.body});
    }
}

fn validateSession(resp: Vapor.Fetch.Result) void {
    if (resp.isOk()) {
        Vapor.println("Session validated {s}", .{resp.Ok.body});
    }
}

fn loginWithProvider(provider: KeyStone.Provider) void {
    KeyStone.signInWithOauth(provider);
}

fn Card() Vapor.Builder(.pure) {
    return Stack()
        .background(.transparentize(.palette(.background), 0.5))
        .border(.round(.palette(.border_color_light), .all(12)))
        .width(.percent(100))
        .padding(.all(16))
        .layout(.top_left)
        .spacing(16);
}

fn onHover(icon: *const Vapor.IconTokens, _: *Vapor.Event) void {
    hovered = icon;
}

fn onLeave(_: *Vapor.Event) void {
    hovered = null;
}

fn AuthBtn(args: KeyStone.Provider, icon: *const Vapor.IconTokens) void {
    Button(loginWithProvider, .{args})
        .size(.hwPx(36, 36))
        .layout(.center)
        .background(.transparentize(.black, 0.8))
        .border(.round(.black, .all(8)))
        .pointer()
        .hover(.{
            .background = .yellow,
            .text_color = .black,
        })
        .onEvent(.pointerenter, onHover, .{icon})
        .onLeave(onLeave)
        .children({
        const active = hovered != null and std.mem.eql(u8, hovered.?.web.?, icon.web.?);
        Vapor.Icon(icon)
            .font(18, 700, if (active) .black else .palette(.alternate_text_color))
            .end();
    });
}

fn payment() void {
    Vapor.Kit.fetch("http://localhost:8080/checkout", handlePayment, .{
        .method = .POST,
        .credentials = "include",
        .headers = .{
            .content_type = "application/x-www-form-urlencoded",
        },
    });
}

fn handlePayment(resp: Vapor.Fetch.Result) void {
    switch (resp) {
        .ok => |data| {
            Vapor.println("Payment data {any}", .{data.body});
            Vapor.redirect(data.body);
        },
        .err => |err| {
            Vapor.println("Failed to fetch payment data: {s}", .{err.message});
        },
    }
    // Vapor.cycle();
}

fn onChange(evt: *Vapor.Event) void {
    evt.preventDefault();
    Vapor.print("onChange {s}", .{evt.text()});
}

pub fn render(login: *Login) void {
    const active_index = Tabs.NavBar("login_tabs", &.{ "Login", "Create Account" });
    const google = KeyStone.keystone.clients.google;
    const github = KeyStone.keystone.clients.github;
    const apple = KeyStone.keystone.clients.apple;
    const auth_providers = if (google != null or github != null or apple != null) true else false;
    Vapor.Spacer(24).end();
    switch (active_index) {
        0 => {
            Card().children({
                Stack()
                    .width(.percent(100))
                    .spacing(8)
                    .children({
                    Text(login.login_title)
                        .font(16, 700, .palette(.text_color))
                        .end();
                    Text(login.login_subtitle)
                        .font(14, 300, .palette(.text_color))
                        .end();
                });

                if (auth_providers) {
                    Box()
                        .width(.percent(100))
                        .spacing(16)
                        .layout(.left_center)
                        .children({
                        if (google) |_| {
                            AuthBtn(KeyStone.Provider.google, .google);
                        }
                        if (github) |_| {
                            AuthBtn(KeyStone.Provider.github, .github);
                        }
                        if (apple) |_| {
                            AuthBtn(KeyStone.Provider.apple, .apple);
                        }
                    });
                }

                Stack()
                    .width(.percent(100))
                    .spacing(16)
                    .children({
                    Field.render(.{ .label = "Email", .value = .{ .email = &details.email }, .type = .email, .id = "email" });
                    Field.render(.{ .label = "Password", .value = .{ .password = &details.password }, .type = .password, .id = "password" });
                });
                Box()
                    .layout(.right_center)
                    .width(.percent(100))
                    .children({
                    Button(submit, .{})
                        .animation("glitch")
                        .background(.transparentize(.black, 0.8))
                        .border(.round(.black, .all(8)))
                        .padding(.all(6))
                        .pointer()
                        .children({
                        Text("Login")
                            .font(16, 300, .palette(.alternate_text_color))
                            .fontFamily("IBM Plex Sans,monospace")
                            .end();
                        Vapor.Svg(.{ .svg = key })
                            .stroke(.palette(.alternate_text_color))
                            .fill(.palette(.text_color))
                            .end();
                    });
                });
            });
        },
        1 => {
            Card().children({
                Stack()
                    .width(.percent(100))
                    .spacing(8)
                    .children({
                    Text(login.create_account_title)
                        .font(16, 700, .palette(.text_color))
                        .end();
                    Text(login.create_account_subtitle)
                        .font(14, 300, .palette(.text_color))
                        .end();
                });
                Stack()
                    .width(.percent(100))
                    .spacing(16)
                    .children({
                    Field.render(.{ .label = "Email", .value = .{ .email = &details.email }, .type = .email });
                    Field.render(.{ .label = "Password", .value = .{ .password = &details.password }, .type = .password });
                });
                Box()
                    .layout(.right_center)
                    .width(.percent(100))
                    .children({
                    Button(createAccount, .{})
                        .animation("glitch")
                        .background(.transparentize(.black, 0.8))
                        .border(.round(.black, .all(8)))
                        .padding(.all(6))
                        .pointer()
                        .children({
                        Text("Create Account")
                            .font(16, 300, .palette(.alternate_text_color))
                            .fontFamily("IBM Plex Sans,monospace")
                            .end();
                        Vapor.Icon(.person_rolodex)
                            .font(16, 700, .palette(.alternate_text_color))
                            .end();
                    });
                });
            });
        },
        else => {},
    }
}
