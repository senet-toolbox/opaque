const std = @import("std");
const Vapor = @import("vapor");
const Box = Vapor.Box;
const Text = Vapor.Text;
const Button = Vapor.Button;
const ButtonCtx = Vapor.ButtonCtx;
const TextField = Vapor.TextField;
const Stack = Vapor.Stack;
const Center = Vapor.Center;
const TextFmt = Vapor.TextFmt;
const Icon = Vapor.Icon;
const Animation = Vapor.Animation;
const Link = Vapor.Link;
const Vaporize = @import("vaporize");

// ============================================================================
// TEENAGE ENGINEERING INSPIRED THEME
// ============================================================================
// Clean, industrial, utilitarian design with orange/teal accents
// Lowercase text, minimal chrome, product-focused

const Theme = struct {
    // Core backgrounds - clean whites and off-whites
    const bg_base = Vapor.Types.Color.palette(.background);
    const bg_light = Vapor.Types.Color.hex("#F5F5F5");
    const bg_cream = Vapor.Types.Color.hex("#FAF9F7");
    const bg_dark = Vapor.Types.Color.palette(.alternate_background);
    const bg_card = Vapor.Types.Color.palette(.background);

    // Accent colors - signature TE orange and teal
    const orange = Vapor.Types.Color.hex("#FF5500");
    const orange_bg = Vapor.Types.Color.hex("#FF5500");
    const teal = Vapor.Types.Color.hex("#006B5A");
    const teal_bg = Vapor.Types.Color.hex("#006B5A");
    const green = Vapor.Types.Color.hex("#2D5A27");
    const green_bg = Vapor.Types.Color.hex("#2D5A27");

    // Text colors
    const text_primary = Vapor.Types.Color.palette(.text_color);
    const text_secondary = Vapor.Types.Color.palette(.text_secondary);
    const text_muted = Vapor.Types.Color.palette(.text_muted);
    const text_light = Vapor.Types.Color.palette(.alternate_text_color);

    // Borders
    const border_light = Vapor.Types.Color.palette(.border_color_light);
    const border_dark = Vapor.Types.Color.palette(.border_color);

    // Font family - using system fonts that feel industrial/utilitarian
    const font_primary = "Inter, -apple-system, sans-serif";
    const font_mono = "JetBrains Mono, SF Mono, monospace";
};

// ============================================================================
// DATA MODELS
// ============================================================================
const ProductCategory = enum {
    all,
    synths,
    speakers,
    accessories,
    collaborations,

    pub fn label(self: ProductCategory) []const u8 {
        return switch (self) {
            .all => "all products",
            .synths => "synthesizers",
            .speakers => "speakers",
            .accessories => "accessories",
            .collaborations => "collaborations",
        };
    }
};

const Product = struct {
    id: usize,
    name: []const u8,
    short_name: []const u8,
    description: []const u8,
    price: u32,
    category: ProductCategory,
    color_accent: ProductAccent,
    in_stock: bool = true,
    new_release: bool = false,
    image: []const u8,
    specs: []const []const u8 = &[_][]const u8{},
};

const ProductAccent = enum {
    orange,
    teal,
    green,
    black,
    cream,

    pub fn bg(self: ProductAccent) Vapor.Types.Color {
        return switch (self) {
            .orange => Theme.orange_bg,
            .teal => Theme.teal_bg,
            .green => Theme.green_bg,
            .black => Theme.bg_dark,
            .cream => Theme.bg_cream,
        };
    }

    pub fn color(self: ProductAccent) Vapor.Types.Color {
        return switch (self) {
            .orange => Theme.orange,
            .teal => Theme.teal,
            .green => Theme.green,
            .black => Theme.text_primary,
            .cream => Theme.text_secondary,
        };
    }
};

const CartItem = struct {
    product_id: usize,
    name: []const u8,
    price: u32,
    quantity: u32,
};

// ============================================================================
// STATE
// ============================================================================
var products: Vapor.Array(Product) = undefined;
var cart: Vapor.Array(CartItem) = undefined;

var selected_category: ProductCategory = .all;
var cart_open: bool = false;
var selected_product_id: ?usize = null;
var hovered_product_id: ?usize = null;

// ============================================================================
// ANIMATIONS
// ============================================================================
const fadeIn = Animation.init("fade-in")
    .prop(.opacity, 0, 1)
    .prop(.translateY, 8, 0)
    .duration(250)
    .easing(.easeOut)
    .fill(.forwards);

const slideRight = Animation.init("slide-right")
    .prop(.translateX, 100, 0)
    .prop(.opacity, 0, 1)
    .duration(300)
    .easing(.easeOut)
    .fill(.forwards);

// ============================================================================
// INIT
// ============================================================================

var vaporizer: Vaporize.Compiler = undefined;

const Validation = Vaporize.Validation;
const ValidationError = Vaporize.ValidationError;

const Currency = enum { usd, eur };

const Country = enum { US, CA, UK };

const PaymentMethod = enum { card, paypal };

const CheckoutForm = struct {
    // Account
    account: struct {
        email: []const u8 = "",
        password: []const u8 = "",
        confirm_password: []const u8 = "",
        contact: struct {
            phone: []const u8 = "",
        } = .{},
    } = .{},

    payment: struct {
        // method: []const u8 = "",
        expiry: []const u8 = "",
        cvv: []const u8 = "",
        billing_address: []const u8 = "",
        card_number: []const u8 = "",
    } = .{},

    shipping_details: struct {
        shipping_same_as_billing: Vaporize.Condition(CheckoutForm) = .{
            .callback = sameAsBilling,
            .target_field = "shipping",
        },
    } = .{},

    shipping: struct {
        address: []const u8 = "",
        // country: []const u8 = "",
        state: []const u8 = "",
        city: []const u8 = "",
        postal_code: []const u8 = "",
    } = .{},

    pub const __validations = .{
        .email = Validation{ .field_type = .email },
        .password = Validation{ .field_type = .password },
        .confirm_password = Validation{ .field_type = .password, .target_field = "password", .match = true },
        .phone = Validation{ .field_type = .telephone, .depends_on = "country" },
        .card_number = Validation{ .field_type = .credit_card },
        .expiry = Validation{ .field_type = .expiry, .placeholder = "MM/YY" },
        .cvv = Validation{ .field_type = .cvv, .placeholder = "123", .err = "CVV is required" },
        .address = Validation{ .field_type = .string, .required = true },
        .city = Validation{ .field_type = .string, .required = true },
        .state = Validation{ .field_type = .string, .required = true },
        .postal_code = Validation{ .field_type = .string, .required = true },
    };

    // pub const __components = .{
    //     .method = PaymentMethodComponent,
    //     .country = CountryComponent,
    // };
};
// fn PaymentMethodComponent(_: *CheckoutForm, _: ?ValidationError) void {
//     payment_method.render();
// }
//
// fn CountryComponent(_: *CheckoutForm, _: ?ValidationError) void {
//     country.render();
// }

fn sameAsBilling(form: *CheckoutForm) void {
    Vapor.print("sameAsBilling {any}", .{form.shipping_details.shipping_same_as_billing.value});
}

fn onSubmit(form: CheckoutForm) void {
    Vapor.print("Submitted {any}", .{form});
}

const FormCheckout = Vaporize.Form(CheckoutForm);
var login_form: FormCheckout = .{ .on_submit = onSubmit };
// var country: Select(Country) = undefined;
// var payment_method: Select(PaymentMethod) = undefined;

pub fn LoginComponent() void {
    renderNavBar();
    login_form.render();
}

pub fn init() void {
    // Vapor.Page(.{ .route = "/ui/te-store" }, renderHome, null);
    Vapor.Page(.{ .route = "/te-store/product" }, renderProductDetail, null);
    Vapor.Page(.{ .route = "/te-store/checkout" }, checkout, null);

    fadeIn.build();
    slideRight.build();

    products = Vapor.array(Product, .persist);
    cart = Vapor.array(CartItem, .persist);

    initProducts();

    vaporizer = Vaporize.init(Vapor.arena(.persist), .{
        .text_field_style = .{
            .visual = .{ .background = Theme.orange_bg },
        },
        .switch_style = .{
            .visual = .{
                .background = Theme.orange_bg,
            },
        },
        .submit_style = .{
            .layout = .center,
            .size = .w(.percent(100)),
            .margin = .{ .top = 32 },
            .visual = .{
                .border = .round(.transparentizeHex(.palette(.alternate_background), 0.5), .all(4)),
                .background = .transparentizeHex(.palette(.alternate_background), 0.9),
                .cursor = .pointer,
                .font_size = 16,
                .text_color = .white,
                .new_shadow = Vapor.Types.NewShadow.init()
                    .inset(0, -2, .transparentizeHex(.palette(.alternate_background), 0.5))
                    .drop(0, 1, 3, .transparentizeHex(.palette(.alternate_background), 0.1)),
            },
            .transition = .{ .duration = 100 },
            .interactive = .{
                .hover = .{
                    .new_shadow = Vapor.Types.NewShadow.init()
                        .inset(0, -2, .transparentizeHex(.black, 0))
                        .drop(0, 1, 3, .transparentizeHex(.black, 0)),
                },
            },
            .padding = .tblr(4, 4, 8, 8),
            .child_gap = 8,
            .font_family = "IBM Plex Sans,monospace",
        },
    }) catch unreachable;

    login_form.compile() catch unreachable;
}

fn initProducts() void {
    const sample_products = [_]Product{
        .{
            .id = 1,
            .name = "EP–40 riddim",
            .short_name = "riddim",
            .description = "a powerful sampler, sequencer and composer inspired by reggae, dub, dancehall and sound system culture. designed for expressive live performance with grid-synced loops and reggae-inspired fx.",
            .price = 329,
            .category = .synths,
            .color_accent = .green,
            .new_release = true,
            .image = "/assets/ep-40.webp",
            .specs = &[_][]const u8{
                "12 stereo / 16 mono poly voices",
                "128MB system memory",
                "subtractive synth engine",
                "grid-synced loops",
                "9 user editable projects",
                "7 main fx and 12 punch-in fx",
                "pressure sensitive keys",
                "sampling frequency: 46 kHz / 16-bit",
            },
        },
        .{
            .id = 2,
            .name = "EP–2350 ting",
            .short_name = "ting",
            .image = "/assets/lenon.webp",
            .description = "a compact fx unit designed to add character and texture to any audio source. features spring reverb emulation, tape delay, and signature dub sirens.",
            .price = 149,
            .category = .synths,
            .color_accent = .orange,
            .new_release = true,
        },
        .{
            .id = 3,
            .name = "riddim shoulder bag",
            .image = "/assets/fusion.webp",
            .short_name = "shoulder bag",
            .description = "custom-designed carrying solution for your EP–40 riddim. features padded interior, cable management, and quick-access pockets.",
            .price = 79,
            .category = .accessories,
            .color_accent = .teal,
        },
        .{
            .id = 4,
            .name = "OP–1 field",
            .short_name = "op–1 field",
            .description = "the next generation all-in-one portable synthesizer, sampler, and multi-track recorder. completely redesigned with new engine, improved audio quality, and enhanced connectivity.",
            .price = 2199,
            .category = .synths,
            .color_accent = .black,
            .image = "/assets/op-1.webp",
            .specs = &[_][]const u8{
                "32-bit / 96 kHz audio",
                "built-in FM radio",
                "accelerometer and gyroscope",
                "8 hours battery life",
                "usb-c audio interface",
            },
        },
        .{
            .id = 5,
            .name = "OB–4 magic radio",
            .image = "/assets/tp-7.webp",
            .short_name = "ob–4",
            .description = "a high-fidelity portable speaker with integrated loop recorder, FM radio, and motorized rewind dial. plays sound from any bluetooth source.",
            .price = 599,
            .category = .speakers,
            .color_accent = .cream,
        },
        .{
            .id = 6,
            .name = "TX–6 ultra-portable pro mixer",
            .short_name = "tx–6",
            .image = "/assets/ep133.webp",
            .description = "the world's smallest professional-grade 6-channel mixer with built-in effects, usb audio interface, and wireless capability.",
            .price = 1199,
            .category = .synths,
            .color_accent = .orange,
        },
        .{
            .id = 7,
            .name = "CM–15 studio mic",
            .short_name = "cm–15",
            .image = "/assets/op-2.webp",
            .description = "broadcast-quality condenser microphone with integrated preamp and digital output. designed for podcasts, music, and field recording.",
            .price = 799,
            .category = .accessories,
            .color_accent = .black,
        },
        .{
            .id = 8,
            .name = "PO–33 K.O!",
            .short_name = "po–33",
            .image = "/assets/tx-6.webp",
            .description = "micro sampler with built-in microphone, 40 second sample memory, 8 melodic slots and 8 drum slots with 16 effects.",
            .price = 89,
            .category = .synths,
            .color_accent = .orange,
        },
    };

    for (sample_products) |product| {
        products.append(product) catch continue;
    }
}

// ============================================================================
// HANDLERS
// ============================================================================
fn toggleCart() void {
    cart_open = !cart_open;
}

fn closeCart() void {
    Vapor.Kit.navigate("/te-store/checkout");
    cart_open = false;
}

fn handleBackdropClick(_: *Vapor.Event) void {
    cart_open = false;
}

fn selectCategory(cat: ProductCategory) void {
    selected_category = cat;
}

fn addToCart(product: *const Product) void {
    for (cart.items) |*item| {
        if (item.product_id == product.id) {
            item.quantity += 1;
            return;
        }
    }

    const name_copy = Vapor.arena(.persist).dupe(u8, product.name) catch return;

    cart.append(.{
        .product_id = product.id,
        .name = name_copy,
        .price = product.price,
        .quantity = 1,
    }) catch return;
}

fn removeFromCart(index: usize) void {
    if (index >= cart.items.len) return;
    _ = cart.orderedRemove(index);
}

fn updateQuantity(index: usize, delta: i32) void {
    if (index >= cart.items.len) return;
    const new_qty = @as(i32, @intCast(cart.items[index].quantity)) + delta;
    if (new_qty <= 0) {
        _ = cart.orderedRemove(index);
    } else {
        cart.items[index].quantity = @intCast(new_qty);
    }
}

fn selectProduct(id: usize) void {
    selected_product_id = id;
    Vapor.Kit.navigate("/te-store/product");
}

fn setHoveredProduct(id: usize, _: *Vapor.Event) void {
    hovered_product_id = id;
}

fn clearHoveredProduct(_: *Vapor.Event) void {
    hovered_product_id = null;
}

fn getCartTotal() u32 {
    var total: u32 = 0;
    for (cart.items) |item| {
        total += item.price * item.quantity;
    }
    return total;
}

fn getCartCount() usize {
    var count: usize = 0;
    for (cart.items) |item| {
        count += item.quantity;
    }
    return count;
}

fn matchesCategory(product: *const Product) bool {
    if (selected_category == .all) return true;
    return product.category == selected_category;
}

fn getProductById(id: usize) ?*const Product {
    for (products.items) |*product| {
        if (product.id == id) return product;
    }
    return null;
}

// ============================================================================
// NAVIGATION BAR - minimal, lowercase, utilitarian
// ============================================================================
fn renderNavBar() void {
    Box()
        .width(.percent(100))
        .height(.px(56 * 2))
        .padding(.horizontal(24))
        .background(Theme.bg_base)
        .layout(.x_between_bottom)
        // .pos(.nav)
        // .zIndex(999)
        .children({
        // Logo - simple lowercase text
        Link(.{ .url = "/ui/templates" })
            .textDecoration(.none)
            .children({
            Text("ryvan engineering")
                .font(14, 400, Theme.text_primary)
                .fontFamily(Theme.font_primary)
                .end();
        });

        // Navigation links - clean, minimal
        Box()
            .layout(.center)
            .spacing(32)
            .children({
            renderNavLink("store", "/ui/templates", true);
            renderNavLink("products", "/ui/templates", false);
            renderNavLink("now", "/ui/templates", false);
            renderNavLink("support", "/ui/templates", false);
        });

        // Cart
        Button(toggleCart)
            .height(.px(32))
            .padding(.horizontal(12))
            .layout(.center)
            .spacing(6)
            .background(.transparent)
            .pointer()
            .children({
            Text("cart")
                .font(14, 400, Theme.text_primary)
                .fontFamily(Theme.font_primary)
                .end();
            if (getCartCount() > 0) {
                TextFmt("({d})", .{getCartCount()})
                    .font(14, 400, Theme.orange)
                    .fontFamily(Theme.font_primary)
                    .end();
            }
        });
    });
}

fn renderNavLink(label: []const u8, url: []const u8, is_active: bool) void {
    Link(.{ .url = url })
        .textDecoration(.none)
        .children({
        Text(label)
            .font(14, 400, if (is_active) Theme.text_primary else Theme.text_secondary)
            .fontFamily(Theme.font_primary)
            .hoverText(Theme.text_primary)
            .duration(100)
            .end();
    });
}

// ============================================================================
// HERO SECTION - Featured product banner
// ============================================================================
fn renderHero() void {
    Box()
        .width(.percent(100))
        .height(.px(480))
        .background(Theme.bg_cream)
        .layout(.x_between_center)
        .padding(.horizontal(48))
        .pos(.relative)
        .children({
        Vapor.Image(.{ .src = "/assets/koii.webp" })
            .pos(.tl(.percent(0), .percent(0), .absolute))
            .width(.percent(100))
            .inlineStyle("object-fit: cover;", .{})
            // .aspectRatio(.landscape)
            .height(.percent(100))
            .end();

        // Left side - product teasers / scattered elements
        Box()
            .width(.px(360))
            .height(.percent(100))
            .layout(.center)
            .pos(.relative)
            .children({
            // Product silhouette placeholder
            Box()
                .width(.px(180))
                .height(.px(200))
                .background(Theme.bg_light)
                .border(.round(Theme.border_light, .all(4)))
                .layout(.center)
                .children({
                Text("[ device ]")
                    .font(12, 400, Theme.text_muted)
                    .fontFamily(Theme.font_mono)
                    .end();
            });
        });

        // Center - decorative elements
        Box()
            .width(.grow)
            .height(.percent(100))
            .layout(.center)
            .pos(.relative)
            .children({
            // // Orange fan/badge graphic placeholder
            // Box()
            //     .width(.px(200))
            //     .height(.px(200))
            //     .background(Theme.orange_bg)
            //     .border(.round(.transparent, .all(100)))
            //     .layout(.center)
            //     .children({
            Text("ryven")
                .font(128, 900, Theme.text_light)
                .fontFamily(Theme.font_primary)
                .end();
            // });
        });

        // Right side - product info card
        Box()
            .width(.px(360))
            .padding(.all(24))
            .background(Theme.bg_cream)
            .pos(.relative)
            .children({
            Stack()
                .spacing(12)
                .children({
                // Brand header
                Box()
                    .layout(.left_center)
                    .spacing(8)
                    .children({
                    Text("RYVEN")
                        .font(32, 900, Theme.text_primary)
                        .fontFamily(Theme.font_primary)
                        .end();
                    Text("SUPERTONE")
                        .font(10, 600, Theme.orange)
                        .fontFamily(Theme.font_primary)
                        .end();
                });

                Text("EP–40")
                    .font(12, 400, Theme.text_secondary)
                    .fontFamily(Theme.font_mono)
                    .end();

                Text("ORIGINAL LAYERING MACHINE")
                    .font(10, 500, Theme.text_muted)
                    .fontFamily(Theme.font_primary)
                    .end();

                Box().height(.px(8)).children({});

                Text("a live loop performance mode, an on-board bass and lead synth, a massive reggae, dub and dancehall sound library.")
                    .font(11, 400, Theme.text_secondary)
                    .fontFamily(Theme.font_primary)
                    .end();
            });
        });
    });
}

// ============================================================================
// HERO LABEL - "riddim n' ting"
// ============================================================================
fn renderHeroLabel() void {
    Box()
        .width(.percent(100))
        .height(.px(200))
        .background(Theme.bg_cream)
        .layout(.bottom_left)
        .padding(.all(24))
        .children({
        Text("riddim n' ting")
            .font(14, 400, Theme.text_primary)
            .fontFamily(Theme.font_primary)
            .end();
    });
}

// ============================================================================
// PRODUCT GRID - Clean, minimal product cards
// ============================================================================
fn renderProductGrid() void {
    Box()
        .width(.percent(100))
        .padding(.all(24))
        .padding(.t(0))
        .background(Theme.bg_base)
        .children({
        // Grid of products
        Box()
            .width(.percent(100))
            .layout(.top_left)
            .wrap(.wrap)
            .children({
            for (products.items) |*product| {
                if (matchesCategory(product)) {
                    renderProductCard(product);
                }
            }
        });
    });
}

fn renderProductCard(product: *const Product) void {
    // const is_hovered = hovered_product_id != null and hovered_product_id.? == product.id;

    // Each card takes roughly 1/3 of width
    Box()
        .width(.percent(25))
        .padding(.all(24))
        .background(Theme.bg_base)
        .direction(.column)
        .spacing(16)
        .border(.bottom(1, Theme.border_light))
        .border(.right(1, Theme.border_light))
        .pointer()
        .onEventCtx(.pointerenter, setHoveredProduct, .{product.id})
        .onEvent(.pointerleave, clearHoveredProduct)
        .animationEnter("fade-in")
        .children({
        // Product name and buy link
        Box()
            .layout(.left_center)
            .spacing(0)
            .direction(.column)
            .children({
            Text(product.name)
                .font(14, 400, Theme.text_primary)
                .fontFamily(Theme.font_primary)
                .end();

            // Buy now link - TE style
            ButtonCtx(addToCart, .{product})
                .background(.transparent)
                .padding(.all(0))
                .pointer()
                .children({
                Text("buy now")
                    .font(14, 400, Theme.orange)
                    .fontFamily(Theme.font_primary)
                    .hoverText(Theme.teal)
                    .duration(100)
                    .end();
            });
        });

        // Product image area - large, clean
        ButtonCtx(selectProduct, .{product.id})
            .width(.percent(100))
            .height(.px(320))
            .background(Theme.bg_base)
            .layout(.center)
            .pointer()
            .duration(200)
            .hover(.{
                .transform = .scaleDecimal(1.02),
            })
            .children({
            // Product placeholder with accent color
            Box()
                .width(.px(200))
                .height(.px(240))
                .background(Theme.bg_light)
                // .border(.round(Theme.border_light, .all(8)))
                .layout(.center)
                .pos(.relative)
                .children({
                // Accent color element
                Vapor.Image(.{ .src = product.image })
                    .pos(.tl(.percent(0), .percent(0), .absolute))
                    .width(.percent(100))
                    .inlineStyle("object-fit: cover;", .{})
                    // .border(.round(.transparent, .all(4)))
                    .height(.percent(100))
                    .end();

                Box()
                    .pos(.tr(.px(8), .px(8), .absolute))
                    .width(.px(24))
                    .height(.px(24))
                    .background(product.color_accent.bg())
                    // .border(.round(.transparent, .all(4)))
                    .children({});

                Text(product.short_name)
                    .pos(.relative)
                    .font(14, 500, Theme.text_secondary)
                    .fontFamily(Theme.font_mono)
                    .end();
            });
        });
    });
}

// ============================================================================
// CATEGORY FILTER - Simple text links
// ============================================================================
fn renderCategoryFilter() void {
    Box()
        .width(.percent(100))
        .padding(.xy(16, 24))
        .background(Theme.bg_base)
        .border(.bottom(1, Theme.border_light))
        .layout(.left_center)
        .spacing(24)
        .children({
        const categories = [_]ProductCategory{ .all, .synths, .speakers, .accessories };
        for (categories) |cat| {
            const is_selected = selected_category == cat;
            ButtonCtx(selectCategory, .{cat})
                .background(.transparent)
                .padding(.all(0))
                .pointer()
                .children({
                Text(cat.label())
                    .font(13, 400, if (is_selected) Theme.text_primary else Theme.text_muted)
                    .fontFamily(Theme.font_primary)
                    .hoverText(Theme.text_primary)
                    .duration(100)
                    .end();
            });
        }
    });
}

// ============================================================================
// CART PANEL - Clean slide-in drawer
// ============================================================================
fn renderCartPanel() void {
    if (!cart_open) return;

    // Backdrop
    Box()
        .pos(.full(.fixed))
        .zIndex(1000)
        .background(.hex("#00000040"))
        .onEvent(.click, handleBackdropClick)
        .children({});

    // Cart panel
    Box()
        .pos(.tr(.px(0), .px(0), .fixed))
        .width(.px(380))
        .height(.percent(100))
        .background(Theme.bg_base)
        .border(.left(1, Theme.border_light))
        .zIndex(1001)
        .direction(.column)
        .animationEnter("slide-right")
        .children({
        // Header
        Box()
            .width(.percent(100))
            .height(.px(56))
            .padding(.horizontal(24))
            .border(.bottom(1, Theme.border_light))
            .layout(.x_between_center)
            .children({
            Text("cart")
                .font(14, 400, Theme.text_primary)
                .fontFamily(Theme.font_primary)
                .end();

            Button(closeCart)
                .width(.px(32))
                .height(.px(32))
                .layout(.center)
                .background(.transparent)
                .pointer()
                .children({
                Text("×")
                    .font(24, 300, Theme.text_secondary)
                    .end();
            });
        });

        // Cart contents
        if (cart.items.len == 0) {
            Center()
                .width(.percent(100))
                .height(.grow)
                .children({
                Text("your cart is empty")
                    .font(14, 400, Theme.text_muted)
                    .fontFamily(Theme.font_primary)
                    .end();
            });
        } else {
            Stack()
                .width(.percent(100))
                .height(.grow)
                .padding(.all(24))
                .spacing(16)
                .children({
                for (cart.items, 0..) |*item, i| {
                    renderCartItem(item, i);
                }
            });

            // Footer with total
            Box()
                .width(.percent(100))
                .padding(.all(24))
                .border(.top(1, Theme.border_light))
                .direction(.column)
                .spacing(16)
                .children({
                Box()
                    .layout(.x_between_center)
                    .children({
                    Text("total")
                        .font(14, 400, Theme.text_secondary)
                        .fontFamily(Theme.font_primary)
                        .end();
                    TextFmt("${d}", .{getCartTotal()})
                        .font(16, 500, Theme.text_primary)
                        .fontFamily(Theme.font_primary)
                        .end();
                });

                Text("ships from the u.s.")
                    .font(12, 400, Theme.text_muted)
                    .fontFamily(Theme.font_primary)
                    .end();

                Button(closeCart)
                    .width(.percent(100))
                    .height(.px(48))
                    .background(Theme.bg_dark)
                    .layout(.center)
                    .pointer()
                    .duration(150)
                    .hover(.{
                        .background = .hex("#333333"),
                    })
                    .children({
                    Text("checkout")
                        .font(14, 400, Theme.text_light)
                        .fontFamily(Theme.font_primary)
                        .end();
                });
            });
        }
    });
}

fn renderCartItem(item: *const CartItem, index: usize) void {
    Box()
        .width(.percent(100))
        .padding(.vertical(16))
        .border(.bottom(1, Theme.border_light))
        .layout(.x_between_center)
        .children({
        Stack()
            .spacing(4)
            .children({
            Text(item.name)
                .font(14, 400, Theme.text_primary)
                .fontFamily(Theme.font_primary)
                .end();
            TextFmt("${d}", .{item.price})
                .font(13, 400, Theme.text_secondary)
                .fontFamily(Theme.font_primary)
                .end();
        });

        Box()
            .layout(.right_center)
            .spacing(12)
            .children({
            // Quantity controls
            Box()
                .layout(.center)
                .spacing(8)
                .children({
                ButtonCtx(updateQuantity, .{ index, @as(i32, -1) })
                    .width(.px(24))
                    .height(.px(24))
                    .layout(.center)
                    .background(.transparent)
                    .border(.round(Theme.border_light, .all(2)))
                    .pointer()
                    .children({
                    Text("–")
                        .font(14, 400, Theme.text_secondary)
                        .end();
                });

                Text(item.quantity)
                    .font(14, 400, Theme.text_primary)
                    .fontFamily(Theme.font_mono)
                    .end();

                ButtonCtx(updateQuantity, .{ index, @as(i32, 1) })
                    .width(.px(24))
                    .height(.px(24))
                    .layout(.center)
                    .background(.transparent)
                    .border(.round(Theme.border_light, .all(2)))
                    .pointer()
                    .children({
                    Text("+")
                        .font(14, 400, Theme.text_secondary)
                        .end();
                });
            });

            // Remove
            ButtonCtx(removeFromCart, .{index})
                .background(.transparent)
                .pointer()
                .children({
                Text("remove")
                    .font(12, 400, Theme.text_muted)
                    .fontFamily(Theme.font_primary)
                    .hoverText(Theme.orange)
                    .duration(100)
                    .end();
            });
        });
    });
}

// ============================================================================
// FOOTER - Simple black bar
// ============================================================================
fn renderFooter() void {
    Box()
        .width(.percent(100))
        .height(.px(120))
        .background(Theme.bg_dark)
        .layout(.center)
        .children({
        Text("© ryvan engineering 2026")
            .font(12, 400, Theme.text_light)
            .fontFamily(Theme.font_primary)
            .end();
    });
}

// ============================================================================
// PRODUCT DETAIL PAGE
// ============================================================================
fn renderProductDetail() void {
    const product = if (selected_product_id) |id| getProductById(id) else null;

    Box()
        .width(.percent(100))
        .height(.percent(100))
        .background(Theme.bg_base)
        .direction(.column)
        .children({
        renderNavBar();

        Stack()
            .width(.percent(100))
            .height(.grow)
            .padding(.t(56))
            // .scroll(.scroll_y())
            .children({
            if (product) |p| {
                Box()
                    .width(.percent(100))
                    .padding(.all(48))
                    .layout(.top_left)
                    .spacing(64)
                    .animationEnter("fade-in")
                    .children({
                    // Left - Product image
                    Box()
                        .width(.px(500))
                        .height(.px(500))
                        .background(Theme.bg_light)
                        .layout(.center)
                        .pos(.relative)
                        .children({
                        // Navigation dots placeholder
                        Box()
                            .pos(.bl(.px(24), .px(24), .absolute))
                            .layout(.left_center)
                            .spacing(8)
                            .children({
                            Box().width(.px(8)).height(.px(8)).background(Theme.bg_dark).border(.round(.transparent, .all(4))).children({});
                            Box().width(.px(8)).height(.px(8)).background(.{ .color = Theme.border_light }).border(.round(.transparent, .all(4))).children({});
                            Box().width(.px(8)).height(.px(8)).background(.{ .color = Theme.border_light }).border(.round(.transparent, .all(4))).children({});
                        });

                        // Product placeholder
                        Box()
                            .width(.px(280))
                            .height(.px(340))
                            .background(Theme.bg_cream)
                            .layout(.center)
                            .pos(.relative)
                            .children({
                            // Accent bar
                            Vapor.Image(.{ .src = p.image })
                                .pos(.tl(.percent(0), .percent(0), .absolute))
                                .width(.percent(100))
                                .inlineStyle("object-fit: cover;", .{})
                                // .border(.round(.transparent, .all(4)))
                                .height(.percent(100))
                                .end();

                            Box()
                                .pos(.tr(.px(0), .px(0), .absolute))
                                .width(.percent(100))
                                .height(.px(8))
                                .background(p.color_accent.bg())
                                .children({});

                            Text(p.short_name)
                                .font(18, 500, Theme.text_secondary)
                                .fontFamily(Theme.font_mono)
                                .end();
                        });
                    });

                    // Right - Product info
                    Stack()
                        .width(.grow)
                        .spacing(24)
                        .children({
                        // Title and price
                        Text(p.name)
                            .font(32, 400, Theme.text_primary)
                            .fontFamily(Theme.font_primary)
                            .end();

                        TextFmt("${d}", .{p.price})
                            .font(24, 400, Theme.text_primary)
                            .fontFamily(Theme.font_primary)
                            .end();

                        Text("ships from the u.s.")
                            .font(14, 400, Theme.text_muted)
                            .fontFamily(Theme.font_primary)
                            .end();

                        // Add to cart button - full width black
                        ButtonCtx(addToCart, .{p})
                            .width(.percent(100))
                            .height(.px(56))
                            .background(Theme.bg_dark)
                            .layout(.center)
                            .pointer()
                            .duration(150)
                            .hover(.{
                                .background = .hex("#333333"),
                            })
                            .children({
                            Text("add to cart")
                                .font(16, 400, Theme.text_light)
                                .fontFamily(Theme.font_primary)
                                .end();
                        });

                        Box().height(.px(16)).children({});

                        // Description
                        Text(p.description)
                            .font(14, 400, Theme.text_secondary)
                            .fontFamily(Theme.font_primary)
                            .end();

                        // Specs
                        if (p.specs.len > 0) {
                            Box().height(.px(8)).children({});

                            Stack()
                                .spacing(8)
                                .children({
                                for (p.specs) |spec| {
                                    Box()
                                        .layout(.left_center)
                                        .spacing(8)
                                        .children({
                                        Text("•")
                                            .font(14, 400, Theme.text_muted)
                                            .end();
                                        Text(spec)
                                            .font(13, 400, Theme.text_secondary)
                                            .fontFamily(Theme.font_primary)
                                            .end();
                                    });
                                }
                            });
                        }
                    });
                });
            } else {
                Center()
                    .width(.percent(100))
                    .height(.px(400))
                    .children({
                    Stack()
                        .layout(.center)
                        .spacing(16)
                        .children({
                        Text("product not found")
                            .font(16, 400, Theme.text_secondary)
                            .fontFamily(Theme.font_primary)
                            .end();

                        Link(.{ .url = "/ui/te-store" })
                            .textDecoration(.none)
                            .children({
                            Text("back to store")
                                .font(14, 400, Theme.orange)
                                .fontFamily(Theme.font_primary)
                                .end();
                        });
                    });
                });
            }

            renderFooter();
        });

        renderCartPanel();
    });
}

// ============================================================================
// CHECKOUT PAGE
// ============================================================================
fn checkout() void {
    Stack()
        .width(.percent(100))
        // .height(.percent(100))
        .background(Theme.bg_base)
        .layout(.top_center)
        .padding(.all(24))
        .children({
        Vapor.Spacer(128).end();
        Stack()
            .width(.percent(45))
            .layout(.top_left)
            .children({
            Text("checkout").font(72, 100, .palette(.text_color))
                .fontFamily(Theme.font_primary)
                .end();
            LoginComponent();
        });
    });
}

// ============================================================================
// HOME PAGE
// ============================================================================
pub fn renderHome() void {
    Box()
        .width(.percent(100))
        // .height(.percent(100))
        .background(Theme.bg_base)
        .direction(.column)
        .children({
        renderNavBar();

        Stack()
            .width(.percent(100))
            .height(.grow)
            .padding(.t(56))
            // .scroll(.scroll_y())
            .children({
            // Hero section with product banner
            // renderHeroLabel();
            renderHero();

            // Category filter
            renderCategoryFilter();

            // Product grid
            renderProductGrid();

            // Footer
            renderFooter();
        });

        renderCartPanel();
    });
}
