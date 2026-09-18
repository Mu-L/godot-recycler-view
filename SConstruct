#!/usr/bin/env python
import os
import sys

from methods import print_error


libname = "godot-recycler-view"
projectdir = "project"

localEnv = Environment(tools=["default"], PLATFORM="")

# Pure-algorithm modules that the standalone doctest runner links.
#
# These compile against godot-cpp's *header-only* containers only — no Godot
# runtime, no RefCounted/Object. That is what lets `scons tests=yes` build a
# plain binary with no engine behind it, so a module only belongs here if it
# has no `#include <godot_cpp/classes/...>` anywhere in its include closure.
# Adding a file that does not meet that bar fails the enum_test_sources() guard
# below with a readable message instead of an unexplained link error.
TEST_SOURCES = [
    "src/diff_algo.cpp",
    "src/fling_scroller.cpp",
    "src/layout_math.cpp",
    "src/op_reorderer.cpp",
    "src/update_op_apply.cpp",
    "src/velocity_tracker.cpp",
]


def enum_test_sources():
    """Validate TEST_SOURCES before the tests env is built.

    Two failure modes, both of which used to surface as a wall of compiler or
    linker errors pointing somewhere unhelpful:
      * a listed path that no longer exists (module renamed or deleted), and
      * a listed module that pulls in Godot-bound classes, which the test
        binary cannot link because it has no Godot runtime.
    """
    for path in TEST_SOURCES:
        if not os.path.isfile(path):
            print_error("tests=yes: TEST_SOURCES lists a missing file: {}".format(path))
            sys.exit(1)
        # Follow one level of local includes: the .cpp plus its sibling header
        # covers every module in this list.
        header = os.path.splitext(path)[0] + ".h"
        for candidate in (path, header):
            if not os.path.isfile(candidate):
                continue
            with open(candidate, "r", encoding="utf-8") as handle:
                body = handle.read()
            if "#include <godot_cpp/classes/" in body or "GDCLASS(" in body:
                print_error(
                    "tests=yes: {} is bound to Godot classes, so it cannot be "
                    "linked into the standalone doctest runner.\n"
                    "    Split its pure logic into a header it can share, and "
                    "list that instead. See TEST_SOURCES in SConstruct.".format(candidate)
                )
                sys.exit(1)


def ensure_godot_cpp_bindings():
    """Generate godot-cpp's bindings when the tests are built on a fresh clone.

    The pure-algorithm modules include godot-cpp's header-only containers
    (godot::Vector), and those transitively include ONE generated header —
    godot_cpp/classes/global_constants.hpp. `godot-cpp/gen/` only exists after
    the extension itself has been built once, so on a fresh clone the tests
    used to die inside godot-cpp's own headers. Generate the headers here
    instead: they are a build artefact, and producing them needs no compiler.
    """
    marker = os.path.join("godot-cpp", "gen", "include", "godot_cpp", "classes", "global_constants.hpp")
    if os.path.isfile(marker):
        return
    print("godot-cpp bindings not generated yet — generating them for the test runner ...")
    sys.path.insert(0, os.path.abspath("godot-cpp/tools"))
    sys.path.insert(0, os.path.abspath("godot-cpp"))
    from build_profile import generate_trimmed_api
    from binding_generator import _generate_bindings

    api_file = os.path.abspath(os.path.join("godot-cpp", "gdextension", "extension_api.json"))
    api = generate_trimmed_api(api_file, "")
    # _generate_bindings writes into <output_dir>/gen, so hand it godot-cpp/
    # itself, matching what godot-cpp's own SConstruct passes.
    _generate_bindings(api, api_file, True, "64", "single", os.path.abspath("godot-cpp"))
    if not os.path.isfile(marker):
        print_error("tests=yes: binding generation did not produce {}".format(marker))
        sys.exit(1)


# Build profiles can be used to decrease compile times.
# You can either specify "disabled_classes", OR
# explicitly specify "enabled_classes" which disables all other classes.
# Modify the example file as needed and uncomment the line below or
# manually specify the build_profile parameter when running SCons.

# localEnv["build_profile"] = "build_profile.json"

customs = ["custom.py"]
customs = [os.path.abspath(path) for path in customs]

opts = Variables(customs, ARGUMENTS)
opts.Update(localEnv)

Help(opts.GenerateHelpText(localEnv))

env = localEnv.Clone()

if not (os.path.isdir("godot-cpp") and os.listdir("godot-cpp")):
    print_error("""godot-cpp is not available within this folder, as Git submodules haven't been initialized.
Run the following command to download godot-cpp:

    git submodule update --init --recursive""")
    sys.exit(1)

# Standalone unit test runner for the pure-algorithm layer (no Godot runtime).
# Usage: scons tests=yes  (works on a fresh clone — see ensure_godot_cpp_bindings)
if ARGUMENTS.get("tests", "no") == "yes":
    enum_test_sources()
    ensure_godot_cpp_bindings()
    test_env = Environment(tools=["default"], PLATFORM="")
    test_env.Append(CPPPATH=[
        "godot-cpp/include",
        "godot-cpp/gen/include",
        "godot-cpp/gdextension",
        "src/",
        "tests/",
    ])
    test_env.Append(CXXFLAGS=["-std=c++17", "-O0", "-g"])
    test_sources = Glob("tests/*.cpp") + TEST_SOURCES
    runner = test_env.Program("tests/bin/test_runner", source=test_sources)
    Default(runner)
    Return()

env = SConscript("godot-cpp/SConstruct", {"env": env, "customs": customs})

env.Append(CPPPATH=["src/"])
sources = Glob("src/*.cpp")

if env["target"] in ["editor", "template_debug"]:
    try:
        doc_data = env.GodotCPPDocData("src/gen/doc_data.gen.cpp", source=Glob("doc_classes/*.xml"))
        sources.append(doc_data)
    except AttributeError:
        print("Not including class reference as we're targeting a pre-4.3 baseline.")

# .dev doesn't inhibit compatibility, so we don't need to key it.
# .universal just means "compatible with all relevant arches" so we don't need to key it.
suffix = env['suffix'].replace(".dev", "").replace(".universal", "")

lib_filename = "{}{}{}{}".format(env.subst('$SHLIBPREFIX'), libname, suffix, env.subst('$SHLIBSUFFIX'))

library = env.SharedLibrary(
    "bin/{}/{}".format(env['platform'], lib_filename),
    source=sources,
)

copy = env.Install("{}/bin/{}/".format(projectdir, env["platform"]), library)

default_args = [library, copy]
Default(*default_args)
