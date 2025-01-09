const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .cpu_features_add = std.Target.wasm.featureSet(&.{.bulk_memory}),
    });

    const sdk_path: std.Build.LazyPath = .{
        .cwd_relative = b.run(&.{ "orca", "sdk-path" }),
    };

    const sample_step = b.step("samples", "Build sample Orca applications");

    const Sample = struct {
        name: []const u8,
        root_source_file: []const u8,
        icon: ?[]const u8 = null,
        resource_dir: ?[]const u8 = null,
    };

    for ([_]Sample{
        .{
            .name = "Triangle",
            .root_source_file = "samples/zig-triangle/src/main.zig",
        },
        .{
            .name = "Sample",
            .root_source_file = "samples/zig-sample/src/main.zig",
            .icon = "samples/zig-sample/icon.png",
            .resource_dir = "samples/zig-sample/data",
        },
        .{
            .name = "UI",
            .root_source_file = "samples/zig-ui/src/main.zig",
            .resource_dir = "samples/zig-ui/data",
        },
    }) |sample| {
        // Module structure:
        //  root = src/orca.zig
        //  app = sample/src/main.zig
        // TODO: modify orca.zig so it can be used as a module instead of taking over the root

        const wasm_lib = b.addStaticLibrary(.{
            .name = "module",
            .root_source_file = b.path("src/orca.zig"),
            .target = wasm_target,
            .optimize = optimize,
        });
        wasm_lib.root_module.addImport("app", b.createModule(.{
            .root_source_file = b.path(sample.root_source_file),
        }));
        wasm_lib.addLibraryPath(sdk_path.path(b, "bin/"));
        wasm_lib.linkSystemLibrary("orca_wasm");

        const run_bundle = b.addSystemCommand(&.{
            "orca",
            "bundle",
            "--name",
            sample.name,
        });
        if (sample.icon) |icon| {
            run_bundle.addArg("--icon");
            run_bundle.addDirectoryArg(b.path(icon));
        }
        if (sample.resource_dir) |res_dir| {
            run_bundle.addArg("--resource-dir");
            run_bundle.addDirectoryArg(b.path(res_dir));
        }
        run_bundle.addArg("--out-dir");
        const bundle_output = run_bundle.addOutputDirectoryArg(sample.name);
        run_bundle.addArtifactArg(wasm_lib);

        sample_step.dependOn(
            &b.addInstallDirectory(.{
                .source_dir = bundle_output.path(b, sample.name), // orca bundle creates a subdir with the app name
                .install_dir = .prefix,
                .install_subdir = sample.name,
            }).step,
        );
    }

    const api_step = b.step("api", "Generate Orca bindings (modifes source tree!)");
    {
        const gen_api = b.addExecutable(.{
            .name = "gen-api",
            .root_source_file = b.path("scripts/gen_api.zig"),
            .target = b.host,
            .optimize = .Debug,
        });

        const run_gen = b.addRunArtifact(gen_api);
        if (b.option([]const u8, "api-path", "Provide a custom api.json") orelse null) |api_path| {
            run_gen.addFileArg(.{ .cwd_relative = api_path });
        } else {
            run_gen.addFileArg(b.path("scripts/api.json")); // TODO should this file be included in the repo?
        }
        const gen_output = run_gen.addOutputFileArg("out.zig"); // TODO temporary path

        const copy_output = b.addWriteFiles();
        copy_output.addCopyFileToSource(gen_output, "out.zig");

        // api_step.dependOn(&copy_output.step);
        const fmt = b.addFmt(.{ .paths = &.{"out.zig"} });
        fmt.step.dependOn(&copy_output.step);
        api_step.dependOn(&fmt.step);
    }
}
