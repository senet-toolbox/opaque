const std = @import("std");
const Vapor = @import("vapor");
const Static = Vapor.Static;
const Types = Vapor.Types;
const Signal = Vapor.Signal;
const Kit = Vapor.Kit;
const println = Vapor.println;
const Binded = Vapor.Element;
const Search = @import("Search.zig");
const Box = Static.Box;
const Image = Static.Image;
const Text = Static.Text;
const Page = Vapor.Page;
const Graphic = Static.Graphic;
const Icon = Static.Icon;
const Button = Static.Button;
const Link = Static.Link;
const List = Static.List;
const CtxButton = Static.CtxButton;
const ListItem = Static.ListItem;
const RedirectLink = Static.RedirectLink;
const Theme = @import("theme");
const IconTokens = Vapor.IconTokens;
const Hooks = Static.Hooks;
const Observer = Vapor.Kit.Observer;
const Stack = Static.Stack;
const Content = @import("../components/Content.zig");
const OverlayManager = @import("../components/OverlayManager.zig");

const SideBar = @This();

const Tag = struct {
    keywords: Keywords = &.{},
    url: []const u8 = "",
    sub_title: []const u8 = "",
    description: []const u8 = "",
};
const Keywords = []const []const u8;
pub const MenuItem = struct {
    id: []const u8,
    title: []const u8,
    sections: []const *const struct { title: []const u8, link: []const u8 } = &.{},
    link: []const u8,
    icon: *const IconTokens,
    tags: []const Tag = &.{},
};

pub const menu_items: []const MenuItem = &.{
    MenuItem{
        .id = "overview",
        .title = "Overview",
        .link = "/docs/vapor",
        .sections = &.{
            &.{ .title = "What is Vapor?", .link = "what-is-vapor" },
            &.{ .title = "Quickstart", .link = "quickstart" },
            &.{ .title = "Vapor is simple", .link = "vapor-is-simple" },
            &.{ .title = "How it works", .link = "how-it-works" },
            &.{ .title = "Why Zig?", .link = "why-zig" },
        },
        .icon = .house, // Keep as is - perfect for home
        .tags = &.{
            Tag{
                .keywords = &.{ "vapor home", "vapor", "docs", "home" },
                .sub_title = "Vapor Docs",
                .url = "/docs/vapor",
                .description = "Vapor documentation...",
            },
        },
    },
    MenuItem{
        .id = "just-let-me-build",
        .title = "Just let me build!!!!",
        .link = "/docs/vapor/concepts/justletmebuild",
        .icon = .fire, // Keep as is - perfect for home
        .tags = &.{
            Tag{
                .keywords = &.{ "started", "installation", "vapor", "immediate", "create app", "vapor create app" },
                .sub_title = "Create an App",
                .url = "/docs/vapor/concepts/justletmebuild/#create-command",
                .description = "Use vapor to create and run an applic...",
            },
        },
    },
    MenuItem{
        .id = "basics",
        .title = "Basics",
        .link = "/docs/vapor/concepts/basics",
        .sections = &.{
            &.{ .title = "Basics", .link = "basics" },
            &.{ .title = "Creating a Vapor App", .link = "creating-a-vapor-app" },
            &.{ .title = "Instantiate", .link = "instantiate" },
        },
        .icon = .mortarboard, // Graduation cap for learning basics
        .tags = &.{
            Tag{
                .keywords = &.{ "basics", "learning", "vapor", "docs", "reconciler", "rendering" },
                .sub_title = "Vapor Basics",
                .url = "/docs/vapor/concepts/basics/#introduction",
                .description = "Introduction to Vapor, and how to use it...",
            },
            Tag{
                .keywords = &.{ "reconciler", "rendering", "rerender" },
                .sub_title = "How rendering works",
                .url = "/docs/vapor/concepts/basics/#reconciler",
                .description = "How the reconciler and rendering of vapor wor...",
            },
        },
    },
    MenuItem{ // Components
        .id = "components",
        .title = "Components",
        .link = "/docs/vapor/concepts/components",
        .icon = .cubes_stacked,
        .tags = &.{
            Tag{
                .keywords = &.{ "components", "ui", "reusable", "state" },
                .sub_title = "Components",
                .url = "/docs/vapor/concepts/components/#components",
                .description = "Components are the building blocks of your application.",
            },
        },
        .sections = &.{
            &.{ .title = "Components", .link = "components" },
            &.{ .title = "Global Components", .link = "global-components" },
            &.{ .title = "Instance Components", .link = "instance-components" },
            &.{ .title = "Function Components", .link = "function-components" },
        },
    },

    MenuItem{ // New to Zig
        .id = "dont-know-zig",
        .title = "From JS to Zig",
        .link = "/docs/vapor/concepts/dont-know-zig",
        .icon = .filetype_js,
        .tags = &.{
            Tag{
                .keywords = &.{ "dont know zig", "zig", "installation", "getting started" },
                .sub_title = "New to Zig",
                .url = "/docs/vapor/concepts/dont-know-zig/#thats-ok",
                .description = "Don't worry, you can still use Vapor!",
            },
        },
        .sections = &.{
            &.{ .title = "That's ok", .link = "thats-ok" },
            &.{ .title = "Basic Variables", .link = "the-basics-variables" },
            &.{ .title = "Functions", .link = "functions" },
            &.{ .title = "The One Weird Type: Strings", .link = "the-one-weird-type-strings" },
            &.{ .title = "If Statements", .link = "if-statements" },
            &.{ .title = "Loops", .link = "loops" },
            &.{ .title = "Structs (Like Objects)", .link = "structs" },
            &.{ .title = "The Dot-Brace Pattern", .link = "the-dot-brace-pattern" },
            &.{ .title = "Printing / Debugging", .link = "printing-debugging" },
            &.{ .title = "You Can Ignore (For Now)", .link = "what-you-can-ignore" },
            &.{ .title = "A Complete Example", .link = "a-complete-example" },
            &.{ .title = "Quick Reference Card", .link = "quick-reference-card" },
            &.{ .title = "Next Steps", .link = "next-steps" },
        },
    },

    MenuItem{
        .id = "project-structure",
        .title = "Project Structure",
        .link = "/docs/vapor/concepts/project",
        .sections = &.{
            &.{ .title = "Project Structure", .link = "project-structure" },
        },
        .icon = .diagram_3,
        .tags = &.{
            Tag{
                .keywords = &.{"routing"},
                .sub_title = "Routes Directory",
                .url = "/docs/vapor/concepts/project/#routes-directory",
                .description = "Routes Directory...",
            },
            Tag{
                .keywords = &.{"web"},
                .sub_title = "Web Directory",
                .url = "/docs/vapor/concepts/project/#web-directory",
                .description = "Web Directory...",
            },
        },
    },

    MenuItem{
        .id = "routing",
        .title = "Routing",
        .link = "/docs/vapor/concepts/routing",
        .sections = &.{
            &.{ .title = "Routing", .link = "routing" },
            &.{ .title = "Page()", .link = "page-sample" },
        },
        .icon = .signpost, // Signpost for navigation/routing
        .tags = &.{
            Tag{
                .keywords = &.{ "dynamic", "routes", "dynamic routes" },
                .sub_title = "Dynamci Routes",
                .url = "/docs/vapor/concepts/routing/#dynamic-routes",
                .description = "Dynamic Routes...",
            },
        },
    },

    MenuItem{
        .id = "styling",
        .title = "Styling",
        .link = "/docs/vapor/concepts/styling",
        .sections = &.{
            &.{ .title = "Styling", .link = "styling" },
            &.{ .title = "New Approach", .link = "new-approach" },
            &.{ .title = "Layout", .link = "layout" },
            &.{ .title = "Two types of styling", .link = "two-types-of-styling" },
            &.{ .title = "Builder functions", .link = "builder-functions" },
            &.{ .title = "Builder patterns", .link = "builder-patterns" },
            &.{ .title = "Style", .link = "style-struct" },
            &.{ .title = "Taking it further", .link = "taking-it-even-further" },
            &.{ .title = "Structs powerful!", .link = "structs-are-insanely-powerful" },
            &.{ .title = "Code Block", .link = "code-block" },
        },
        .icon = .paint_bucket, // Circular arrows for reactive updates
    },

    MenuItem{
        .id = "reactivity",
        .title = "Reactivity",
        .link = "/docs/vapor/concepts/reactivity",
        .sections = &.{
            &.{ .title = "Reactivity", .link = "reactivity" },
            &.{ .title = "UI as reactivity", .link = "ui-as-reactivity" },
            &.{ .title = "Atomic Mode", .link = "atomic-mode" },
            &.{ .title = "Immediate Mode", .link = "immediate-mode" },
            &.{ .title = "80% of content in an application is static", .link = "80-content-is-static" },
            &.{ .title = "Retained Mode", .link = "retained-mode" },
            &.{ .title = "Using cycle()", .link = "using-cycle" },
            &.{ .title = "Zig is meant to be Explicit!", .link = "zig-is-meant-to-be-explicit" },
            &.{ .title = "Signal(T)", .link = "signalT" },
            &.{ .title = "Effects", .link = "effects" },
            &.{ .title = "With the concept of effects", .link = "with-the-concept-of-effects" },
            &.{ .title = "Without the concept of effects", .link = "without-the-concept-of-effects" },
            &.{ .title = "Its just Zig", .link = "its-just-zig" },
        },
        .icon = .arrow_repeat, // Circular arrows for reactive updates
        .tags = &.{
            Tag{
                .keywords = &.{ "ui to code", "ui reactivity" },
                .sub_title = "UI to Code",
                .url = "/docs/vapor/concepts/reactivity/#ui-to-code",
                .description = "Going from UI to Code...",
            },
        },
    },

    MenuItem{
        .id = "common-patterns",
        .title = "Common Patterns",
        .link = "/docs/vapor/concepts/common-patterns",
        .icon = .filetype_js,
        .tags = &.{
            Tag{
                .keywords = &.{ "common", "patterns", "ui", "hooks", "mounted", "unmounted", "initialization", "custom", "components" },
                .sub_title = "Common Patterns",
                .url = "/docs/vapor/concepts/common-patterns/#common-patterns",
                .description = "Common Patterns",
            },
        },
        .sections = &.{
            &.{ .title = "Common Patterns", .link = "common-patterns" },
            &.{ .title = "Form Handling & User Input", .link = "form-handling" },
            &.{ .title = "Keyboard Events in Forms", .link = "keyboard-events-in-forms" },
            &.{ .title = "Todo List Example", .link = "todo-list-example" },
        },
    },

    MenuItem{
        .id = "gotchas",
        .title = "Gotchas",
        .link = "/docs/vapor/concepts/gotchas",
        .icon = .exclamation_circle,
        .tags = &.{
            Tag{
                .keywords = &.{ "gotchas", "common", "mistakes", "pitfalls", "avoid", "vapor" },
                .sub_title = "Gotchas",
                .url = "/docs/vapor/concepts/gotchas/#gotchas",
                .description = "Gotchas & Common Mistakes",
            },
        },
        .sections = &.{
            &.{ .title = "Gotchas", .link = "gotchas" },
            &.{ .title = "String Slices Are References, Not Copies", .link = "string-slice-gotcha" },
            &.{ .title = "Style Struct vs Builder Chain Syntax", .link = "style-syntax-gotcha" },
            &.{ .title = "Event Handler Signatures", .link = "event-handler-gotcha" },
            &.{ .title = "State Inside Render Functions", .link = "state-in-render-gotcha" },
            &.{ .title = "Color vs Background Types", .link = "color-type-gotcha" },
            &.{ .title = "Loop Index vs Value", .link = "loop-index-gotcha" },
        },
    },

    MenuItem{ // Vaporize
        .id = "Vaporize",
        .title = "Vaporize",
        .link = "/docs/vapor/concepts/vaporize",
        .sections = &.{
            &.{ .title = "Vaporize", .link = "vaporize" },
        },
        .icon = .device_hdd_fill,
    },
    MenuItem{
        .id = "animation",
        .title = "Animation",
        .link = "/docs/vapor/concepts/animation",
        .sections = &.{
            &.{ .title = "Animation", .link = "animation" },
            &.{ .title = "Quick Start", .link = "quick-start" },
            &.{ .title = "Core Concepts", .link = "core-concepts" },
            &.{ .title = "Property Types", .link = "property-types" },
            &.{ .title = "Basic Animations", .link = "basic-animations" },
            &.{ .title = "Timing Controls", .link = "timing-controls" },
            &.{ .title = "Easing Functions", .link = "easing-functions" },
            &.{ .title = "Key Frames", .link = "keyframe-animations" },
            &.{ .title = "Units", .link = "units" },
            &.{ .title = "Presets", .link = "presets" },
            &.{ .title = "Exit Animations", .link = "exit-animations" },
            &.{ .title = "Transitions", .link = "transitions" },
            &.{ .title = "Complete Example", .link = "complete-example" },
            &.{ .title = "API Reference", .link = "api-reference" },
            &.{ .title = "Best Practices", .link = "best-practices" },
        },
        .icon = .film, // Keep as is - perfect for home
        .tags = &.{
            Tag{
                .keywords = &.{"animation"},
                .sub_title = "Animation Docs",
                .url = "/docs/vapor/concepts/animation",
                .description = "Animation documentation...",
            },
        },
    },

    MenuItem{ // New to Zig
        .id = "new-to-zig",
        .title = "Deep Dive",
        .link = "/docs/vapor/concepts/new-to-zig",
        .icon = .microscope,
        .tags = &.{
            Tag{
                .keywords = &.{ "new to zig", "zig", "installation", "getting started" },
                .sub_title = "New to Zig",
                .url = "/docs/vapor/concepts/new-to-zig/#new-to-zig",
                .description = "New to Zig...",
            },
        },
        .sections = &.{
            &.{ .title = "New to Zig", .link = "new-to-zig" },
            &.{ .title = "Memory", .link = "memory" },
        },
    },

    MenuItem{ // Memory
        .id = "memory",
        .title = "Memory",
        .link = "/docs/vapor/concepts/memory",
        .sections = &.{
            &.{ .title = "Memory", .link = "memory" },
        },
        .icon = .memory,
    },
    MenuItem{
        .id = "layout",
        .title = "Layout",
        .link = "/docs/vapor/concepts/layout",
        .icon = .columns, // Circular arrows for reactive updates
        .sections = &.{
            &.{ .title = "Layouts", .link = "layouts" },
            &.{ .title = "Register Layouts", .link = "register-layout" },
        },
        .tags = &.{
            Tag{
                .keywords = &.{ "layout", "defaults", "spacing", "overlay" },
                .sub_title = "Introduction",
                .url = "/docs/vapor/concepts/layout/#introduction",
                .description = "How to use layouts...",
            },
        },
    },
    MenuItem{
        .id = "kit",
        .title = "Kit",
        .link = "/docs/vapor/concepts/kit",
        .icon = .tools, // Tools icon for toolkit/kit
        .sections = &.{
            &.{ .title = "Kit", .link = "kit" },
            &.{ .title = "Why Callbacks again?", .link = "why-callbacks" },
            &.{ .title = "Example", .link = "example" },
            &.{ .title = "fetch", .link = "fetch" },
            &.{ .title = "fetchCtx", .link = "fetchCtx" },
            &.{ .title = "navigate", .link = "navigate" },
            &.{ .title = "routePush", .link = "routePush" },
            &.{ .title = "getWindowPath", .link = "getWindowPath" },
            &.{ .title = "getWindowParams", .link = "getWindowParams" },
            &.{ .title = "persist", .link = "persist" },
            &.{ .title = "getPersist", .link = "getPersist" },
        },
    },
    MenuItem{
        .id = "events-and-handlers",
        .title = "Events & Handlers",
        .link = "/docs/vapor/concepts/events",
        .icon = .cursor,
        .sections = &.{
            &.{ .title = "Events and Handlers", .link = "events-and-handlers" },
            &.{ .title = "Basic event listener", .link = "basic-event-listener" },
            &.{ .title = "Binded event listener", .link = "binded-event-listener" },
            &.{ .title = "Type safety", .link = "type-safety" },
            &.{ .title = "Field saftey", .link = "field-saftey" },
        },
    },
    MenuItem{
        .id = "lifecycle-hooks",
        .title = "Lifecycle Hooks",
        .link = "/docs/vapor/concepts/hooks",
        .sections = &.{
            &.{ .title = "Hooks", .link = "hooks-overview" },
            &.{ .title = "Router Hooks", .link = "router-hooks" },
            &.{ .title = "Hook Context", .link = "hook-context" },
            &.{ .title = "Register Hooks", .link = "register-hook" },
            &.{ .title = "Lifecycle Hooks", .link = "lifecycle-hooks" },
            &.{ .title = "Component Hooks", .link = "component-hooks" },
            &.{ .title = "Tree Hooks", .link = "tree-hooks" },
            &.{ .title = "OnEnd", .link = "onend" },
            &.{ .title = "OnCommit", .link = "oncommit" },
        },
        .icon = .hourglass_split,
    },
    MenuItem{
        .id = "theme-and-icons",
        .title = "Theme and Icons",
        .link = "/docs/vapor/concepts/theme-and-icons",
        .icon = .palette,
        .tags = &.{
            Tag{
                .keywords = &.{ "theme", "icons", "vapor", "ui" },
                .sub_title = "Theme and Icons",
                .url = "/docs/vapor/concepts/theme-and-icons",
                .description = "Theme and Icons",
            },
        },
        .sections = &.{
            &.{ .title = "Theme and Icons", .link = "theme-and-icons" },
            &.{ .title = "Theme System", .link = "theme-system" },
            &.{ .title = "Using Theme Colors", .link = "using-theme-colors" },
            &.{ .title = "Registering Themes", .link = "registering-themes" },
            &.{ .title = "Color Formats", .link = "color-formats" },
            &.{ .title = "Icon System", .link = "icon-system" },
            &.{ .title = "Complete Example", .link = "complete-example" },
            &.{ .title = "Benefits Over External Libraries", .link = "benefits-over-external-libraries" },
        },
    },
    MenuItem{
        .id = "react-to-vapor",
        .title = "React to Vapor",
        .link = "/react-to-vapor",
        .icon = .react,
        .tags = &.{
            Tag{
                .keywords = &.{ "react", "vapor", "ui", "javascript", "typescript", "react-to-vapor", "react-ui" },
                .sub_title = "React to Vapor",
                .url = "/react-to-vapor",
                .description = "React to Vapor",
            },
        },
    },
    MenuItem{
        .id = "Codex Engine",
        .title = "Codex Engine",
        .link = "/docs/vapor/concepts/codex-engine",
        .sections = &.{
            &.{ .title = "Codex Engine", .link = "codex-engine" },
            &.{ .title = "How it works", .link = "how-it-works" },
            &.{ .title = "An Example", .link = "example" },
            &.{ .title = "Comparison to Typical Frameworks", .link = "comparison-to-typical-frameworks" },
            &.{ .title = "Vapor Difference", .link = "vapor-difference" },
            &.{ .title = "Instructions vs Information", .link = "instructions-vs-information" },
        },
        .icon = .motherboard,
    },
    MenuItem{
        .id = "performance",
        .title = "Performance",
        .link = "/docs/vapor/concepts/performance",
        .icon = .ethernet,
        .tags = &.{
            Tag{
                .keywords = &.{ "performance", "auth", "authentication", "login", "signup", "registration", "login", "signup", "registration" },
                .sub_title = "Performance is the Auth system",
                .url = "/docs/vapor/concepts/reactivity/#sign-up",
                .description = "How to sign up and login with Oauth...",
            },
        },
        .sections = &.{
            &.{ .title = "Performance", .link = "performance" },
            &.{ .title = "Memory", .link = "memory" },
            &.{ .title = "Speed", .link = "speed-runtime" },
            &.{ .title = "Default Mode", .link = "default-mode" },
            &.{ .title = "Fullstack", .link = "full-stack" },
        },
    },
    MenuItem{
        .id = "tutorials",
        .title = "Tutorials",
        .link = "/docs/vapor/concepts/tutorials",
        .icon = .chart_steps,
        .tags = &.{
            Tag{
                .keywords = &.{ "tutorials", "tic-tac-toe", "react-to-vapor", "dont-know-zig", "vapor-tictactoe-tutorial" },
                .sub_title = "Tic-Tac-Toe Tutorial",
                .url = "/docs/vapor/concepts/tutorials/#vapor-tictactoe-tutorial",
                .description = "Build a Tic-Tac-Toe game with Vapor.",
            },
        },
        .sections = &.{
            &.{ .title = "Tic-Tac-Toe Tutorial", .link = "vapor-tictactoe-tutorial" },
            &.{ .title = "Prerequisites", .link = "prerequisites" },
            &.{ .title = "Project Setup", .link = "project-setup" },
            &.{ .title = "Game State", .link = "game-state" },
            &.{ .title = "Render the Game Board", .link = "render-board" },
            &.{ .title = "Create the Board Grid", .link = "board-grid" },
            &.{ .title = "Game Logic", .link = "game-logic" },
            &.{ .title = "Display the winner & reset button", .link = "status-display" },
            &.{ .title = "Styling", .link = "styling" },
            &.{ .title = "Winning Animation", .link = "winning-animation" },
            &.{ .title = "Complete Source", .link = "complete-code" },
            &.{ .title = "What's Next", .link = "whats-next" },
            &.{ .title = "Api Quick Reference", .link = "api-quick-reference" },
            &.{ .title = "Challenges", .link = "challenges" },
            &.{ .title = "Key Takeaway", .link = "key-takeaways" },
        },
    },
    MenuItem{
        .id = "api",
        .title = "API Cheat Sheet",
        .link = "/docs/vapor/concepts/api",
        .icon = .filetype_json,
        .tags = &.{
            Tag{
                .keywords = &.{ "api", "cheat", "sheet", "vapor" },
                .sub_title = "API Cheat Sheet",
                .url = "/docs/vapor/concepts/api",
                .description = "API Cheat Sheet",
            },
        },
        .sections = &.{
            &.{ .title = "Cheat-Sheet", .link = "vapor-api-cheatsheet" },
            &.{ .title = "Imports", .link = "imports-and-setup" },
            &.{ .title = "Application Intialization", .link = "application-initialization" },
            &.{ .title = "State Management", .link = "state-management" },
            &.{ .title = "Component Patterns", .link = "component-patterns" },
            &.{ .title = "Core Components", .link = "core-components" },
            &.{ .title = "Styling Reference", .link = "styling-reference" },
            &.{ .title = "Style Structs", .link = "style-structs" },
            &.{ .title = "Events and Handlers", .link = "events-and-handlers" },
            &.{ .title = "Memory Arenas", .link = "memory-arenas" },
            &.{ .title = "Dynamic Arrays", .link = "dynamic-arrays" },
            &.{ .title = "Routing", .link = "routing" },
            &.{ .title = "Animations", .link = "animations" },
            &.{ .title = "Binded Elements", .link = "binded-elements" },
            &.{ .title = "Conditionals and Loops", .link = "conditionals-and-loops" },
            &.{ .title = "Utility Functions", .link = "utility-functions" },
            &.{ .title = "Quick Syntax Reference", .link = "quick-syntax-reference" },
            &.{ .title = "Common Patterns", .link = "common-patterns" },
        },
    },
    MenuItem{
        .id = "metal",
        .title = "Metal",
        .link = "/docs/metal",
        .icon = .screw_driver, // Graduation cap for learning basics
        .tags = &.{
            Tag{
                .keywords = &.{ "metal", "docker" },
                .sub_title = "No more Docker",
                .url = "/docs/metal/#introduction",
                .description = "Senet, and all its sub frameworks run on metal, no docker...",
            },
        },
    },
};

var current_menu_item: ?MenuItem = null;
var current_section: []const u8 = "";
var sections: std.StringHashMap(bool) = undefined;
pub var section_indices: std.AutoHashMap(usize, void) = undefined;
pub fn init() void {
    sections = std.StringHashMap(bool).init(Vapor.lib.frame_arena.persistentAllocator());
    section_indices = std.AutoHashMap(usize, void).init(Vapor.lib.frame_arena.persistentAllocator());
    Content.initBoxes();
    observer = Observer.new("menu-bar", handleSection, .{
        .threshold = 0.4,
    });
}

fn openDialog() void {
    Search.toggle();
}

fn toggleTheme() void {
    Theme.toggleTheme();
}

pub fn goto(url: []const u8) void {
    sections.clearRetainingCapacity();
    for (menu_items) |item| {
        if (std.mem.eql(u8, url, item.link)) {
            current_menu_item = item;
            for (item.sections) |section| {
                sections.put(section.link, false) catch unreachable;
            }
        }
    }
    Vapor.navigate(url);
    Vapor.scrollTo(0, 0);
    Vapor.onLayout(reinit, .{}); // This will triger at the end of the current cycle
}

fn handlePopState() void {
    const url = Vapor.currentPath();
    sections.clearRetainingCapacity();
    for (menu_items) |item| {
        if (std.mem.eql(u8, url, item.link)) {
            current_menu_item = item;
            for (item.sections) |section| {
                sections.put(section.link, false) catch unreachable;
            }
        }
    }
    Vapor.scrollTo(0, 0);
    reinit(); // This will triger at the end of the current cycle
}

fn handleSection(target: Observer.Target) void {
    if (Content.boxes.len == 0) return;
    if (Content.boxes.len > target.index) {
        if (target.is_in_view) {
            sections.put(current_menu_item.?.sections[target.index].link, true) catch |err| {
                Vapor.print(.err, "{any}", .{err});
                return;
            };
            Content.boxes[target.index].active = true;
        } else {
            _ = sections.remove(current_menu_item.?.sections[target.index].link);
            Content.boxes[target.index].active = false;
        }
    }
}

pub fn reinit() void {
    if (!Vapor.getStatus().valid_url) return;
    observer.disconnect();
    Content.reinitBoxes(); // This creates the boxes after the page is mounted
    Vapor.cycle();
    reinitObserver(); // This will triger at the end of the current cycle

}
var mounted: bool = false;

var observer: Observer = undefined;
fn createObserver() void {
    if (!Vapor.getStatus().valid_url) return;
    Content.reinitBoxes(); // This creates the boxes after the page is mounted

    if (current_menu_item) |item| {
        for (item.sections, 0..) |section, i| {
            observer.observe(.{ .uuid = section.link }, i);
        }
    }
}

fn reinitObserver() void {
    if (current_menu_item) |item| {
        for (item.sections, 0..) |section, i| {
            observer.observe(.{ .uuid = section.link }, i);
        }
    }
}

fn mount() void {
    mounted = true;
    Vapor.scrollTo(0, 0);
    // this runs after the vaporize is mounter
    const current_path = Vapor.currentPath();
    current_menu_item = null;
    for (menu_items) |item| {
        if (std.mem.eql(u8, current_path, item.link)) {
            current_menu_item = item;
            for (item.sections) |section| {
                sections.put(section.link, false) catch unreachable;
            }
            break;
        }
    }

    if (current_menu_item == null) return;
    const uuid = Vapor.fmtln("menu-{s}", .{current_menu_item.?.link});
    Vapor.scrollIntoView(uuid, .{ .block = .start });
    if (!Vapor.getStatus().valid_url) return;
    Vapor.onLayout(createObserver, .{});
    Vapor.onPopState(handlePopState);
}

fn home() void {
    Vapor.navigate("/");
    Vapor.scrollTo(0, 0);
}

fn list() void {
    const current_path = Vapor.currentPath();
    Vapor.Static.HooksCtx(.mounted, mount, .{})({
        Box().style(&.{
            .layout = .x_between_center,
            .child_gap = 8,
            .padding = .{ .top = 8, .bottom = 8, .left = 12, .right = 12 },
            .position = .{ .type = .fixed, .top = .px(0), .left = .percent(8), .right = .percent(0), .z_index = 400 },
            .size = .hw(.mobileDesktopPercent(8, 6), .percent(100 - 8)),
            .visual = .{
                .blur = 3,
            },
        }).children({
            Box().style(&.{
                .layout = .x_between_center,
                .child_gap = 8,
                .size = .h(.percent(100)),
            }).children({
                Button(home)
                    // Link(.{ .url = "/", .aria_label = "home page of tether" })
                    .style(&.{
                        .visual = .{ .text_decoration = .none, .cursor = .pointer },
                    }).children({
                    Image(.{ .src = "/assets/circlelogo.webp", .alt = "tether logo" }).style(&.{
                        .layout = .center,
                        .size = .squarePx(42),
                    }).end();
                });
                Text("Senet").style(&.{
                    .visual = .{ .font_weight = 500, .font_size = 18 },
                }).end();
                Box().style(&.{
                    .visual = .{ .border = .left(1, .rgb(0, 0, 0)) },
                    .size = .{ .height = .px(24) },
                }).children({});
                Text("Docs").style(&.{
                    .visual = .{ .font_weight = 700, .font_size = 18 },
                }).end();
            });
            if (!Vapor.isMobile()) {
                Button(openDialog)
                    .ariaLabel("search-dialog")
                    .style(&.{
                        .layout = .x_between_center,
                        .size = .hw(.px(38), .percent(50)),
                        .padding = .xy(8, 4),
                        .visual = .{ .border = .thin(.hex("#E1E1E1")), .background = .transparent, .cursor = .pointer },
                        .interactive = .{ .hover = .{
                            .border = .thin(.palette(.tint)),
                        } },
                    }).background(.palette(.background)).children({
                    Box().style(&.{ .layout = .left_center, .child_gap = 24 }).children({
                        Icon(.search).style(&.{
                            .visual = .{ .font_size = 16, .text_color = .palette(.icon_color) },
                        }).end();
                        Text("Search...").style(&.{
                            .visual = .{ .font_size = 16, .text_color = .palette(.icon_color) },
                            .font_family = "Montserrat, sans-serif",
                        }).end();
                    });
                    Icon(.command).style(&.{
                        .visual = .{ .font_size = 16, .text_color = .palette(.icon_color) },
                    }).end();
                });
                // Box().plain();
                Box().style(&.{
                    .size = .{ .width = .percent(20), .height = .percent(100) },
                    .layout = .right_center,
                    .padding = .horizontal(12),
                    .child_gap = 24,
                }).children({
                    Button(toggleTheme)
                        .ariaLabel("toggle theme")
                        .style(&.{
                            .visual = .{ .background = .transparent, .cursor = .pointer },
                        }).children({
                        Icon(.cloud_moon).style(&.{
                            .visual = .{ .font_size = 24, .text_color = .palette(.icon_color) },
                            .interactive = .{ .hover = .{ .text_color = .palette(.tint) } },
                        }).end();
                    });
                });
            }
        });
        Box().style(&.{
            .position = .{ .type = .fixed, .top = if (Vapor.isMobile()) .percent(8) else .percent(8), .left = .percent(8), .z_index = 999 },
            .size = .hw(.percent(100), .mobileDesktopPercent(100, 14)),
        }).children({
            List().style(&.{
                .list_style = .none,
                .direction = .column,
                .padding = .{ .top = 16, .bottom = 64, .right = 8, .left = 8 },
                .child_gap = 12,
                .size = .hw(.percent(95), .percent(100)),
                .scroll = .scrollY(),
                .show_scrollbar = false,
                .layout = .{},
            }).children({
                for (menu_items) |item| {
                    const uuid = Vapor.fmtln("menu-{s}", .{item.link});
                    ListItem()
                        .id(uuid)
                        .style(&.{
                            .size = .hw(.fit, .percent(100)),
                            .visual = .{
                                .background = if (std.mem.eql(u8, current_path, item.link)) .transparentize(.palette(.tint), 0.1) else .transparent,
                                .border = .right(1, if (std.mem.eql(u8, current_path, item.link)) .palette(.tint) else .transparent),
                                .layer = if (std.mem.eql(u8, current_path, item.link)) .dot(0.5, 6, .transparentize(.palette(.tint), 0.3)) else null,
                            },
                            .interactive = .{
                                .hover = .{
                                    .background = if (std.mem.eql(u8, current_path, item.link)) .transparentize(.palette(.tint), 0.1) else .palette(.highlight_color),
                                },
                            },
                        }).children({
                        CtxButton(goto, .{item.link}).style(&.{
                            .visual = .{
                                .text_decoration = .none,
                                .cursor = .pointer,
                                .background = .transparent,
                            },
                            .size = .w(.percent(100)),
                            .layout = .left_center,
                            .child_gap = 12,
                            .padding = .xy(8, 10),
                        }).children({
                            if (item.icon == Vapor.IconTokens.cubes_stacked or item.icon == Vapor.IconTokens.microscope or item.icon == Vapor.IconTokens.react) {
                                Vapor.Svg(.{ .svg = item.icon.svg.?, .override = true }).style(&.{
                                    .size = .{ .width = .px(16), .height = .px(16) },
                                    .visual = .{
                                        .fill = if (std.mem.eql(u8, current_path, item.link)) .palette(.tint) else .palette(.text_color),
                                    },
                                }).end();
                            } else {
                                Icon(item.icon).style(&.{
                                    .size = .{ .width = .px(14), .height = .px(14) },
                                    .visual = .{ .text_color = if (std.mem.eql(u8, current_path, item.link)) .palette(.tint) else .palette(.text_color) },
                                }).end();
                            }
                            Text(item.title).style(&.{
                                .visual = .{
                                    .text_color = if (std.mem.eql(u8, current_path, item.link)) .palette(.tint) else .palette(.text_color),
                                    .font_size = 14,
                                },
                                .font_family = "Montserrat",
                            }).end();
                        });
                    });
                }
            });
        });
        Stack().style(&.{
            .position = .{ .type = .fixed, .top = if (Vapor.isMobile()) .percent(8) else .percent(8), .right = .percent(2), .z_index = 999 },
            .size = .hw(.percent(100), .mobileDesktopPercent(100, 14)),
        }).children({
            Box().style(&.{
                .layout = .left_center,
                .child_gap = 8,
            }).children({
                Icon(.list_task).font(20, 500, .palette(.text_color)).end();
                Text("On this page").font(16, 500, .palette(.text_color)).end();
            });
            List().style(&.{
                .list_style = .none,
                .direction = .column,
                .padding = .{ .top = 16, .bottom = 64, .right = 0, .left = 0 },
                .child_gap = 8,
                .size = .hw(.percent(95), .percent(100)),
                .scroll = .scrollY(),
                .show_scrollbar = false,
                .layout = .{},
            }).children({
                if (current_menu_item) |current| {
                    for (current.sections) |section| {
                        const url = Vapor.fmtln("#{s}", .{section.link});
                        const active_section = sections.get(section.link) orelse false;
                        const title = section.title;
                        const text_color: Vapor.Types.Color = if (active_section) .palette(.tint) else .palette(.text_color);
                        ListItem().hw(.fit, .percent(100))
                            .children({
                            Link(.{ .url = url, .aria_label = title })
                                .pointer()
                                .noDecoration()
                                .cursor(.pointer)
                                .border(.left(2, if (active_section) .palette(.tint) else .transparent))
                                .pl(6)
                                .width(.full)
                                .layout(.left_center)
                                .children({
                                Text(title)
                                    .font(14, 300, text_color)
                                    .end();
                            });
                        });
                    }
                }
            });
        });
    });
    Search.render();
}

pub fn render() void {
    Box().style(&.{
        .position = .nav,
        .size = .hw(.percent(100), .mobileDesktopPercent(100, 14)),
        .padding = .{ .bottom = 128 },
    }).children({
        list();
    });
}
