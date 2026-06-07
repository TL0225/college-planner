#!/usr/bin/env python3
"""Strip test targets and xcconfig refs from College.xcodeproj for GitHub-only app checkout."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBX = ROOT / "College.xcodeproj/project.pbxproj"
SCHEME = ROOT / "College.xcodeproj/xcshareddata/xcschemes/College.xcscheme"

ARCH_IN_BUILD_SETTINGS = (
    "\t\t\t\tARCHS = arm64;\n"
    '\t\t\t\t"EXCLUDED_ARCHS[sdk=macosx*]" = x86_64;\n'
    "\t\t\t\tMICROSOFT_CLIENT_ID = YOUR_AZURE_CLIENT_ID_HERE;\n"
)

# PBX object UUID prefixes (first 24 chars of IDs in project.pbxproj)
REMOVE_OBJECT_IDS = [
    "1C74876F2EF688EC00021529",  # CollegeTests.xctest
    "1C7487792EF688EC00021529",  # CollegeUITests.xctest
    "CC0000012F0D000000000001",  # Config.xcconfig
    "CC0000022F0D000000000002",  # Secrets.xcconfig.example
    "1C7487722EF688EC00021529",  # CollegeTests sync group
    "1C74877C2EF688EC00021529",  # CollegeUITests sync group
    "1C74878F2EF6B53100021529",  # Pages sync group
    "1C74876E2EF688EC00021529",  # CollegeTests target
    "1C7487782EF688EC00021529",  # CollegeUITests target
    "1C74876C2EF688EC00021529",  # CollegeTests Frameworks
    "1C7487762EF688EC00021529",  # CollegeUITests Frameworks
    "1C74876B2EF688EC00021529",  # CollegeTests Sources
    "1C7487752EF688EC00021529",  # CollegeUITests Sources
    "1C74876D2EF688EC00021529",  # CollegeTests Resources
    "1C7487772EF688EC00021529",  # CollegeUITests Resources
    "1C7487702EF688EC00021529",  # ContainerItemProxy
    "1C74877A2EF688EC00021529",  # ContainerItemProxy
    "1C7487712EF688EC00021529",  # TargetDependency
    "1C74877B2EF688EC00021529",  # TargetDependency
    "1C7487872EF688EC00021529",  # CollegeTests Debug config
    "1C7487882EF688EC00021529",  # CollegeTests Release config
    "1C74878A2EF688EC00021529",  # CollegeUITests Debug config
    "1C74878B2EF688EC00021529",  # CollegeUITests Release config
    "1C7487862EF688EC00021529",  # CollegeTests config list
    "1C7487892EF688EC00021529",  # CollegeUITests config list
    "1C1B1EE52EFF73BC00849BEC",  # SwiftSoup (test-only duplicate)
    "AA0003032F0C000000000003",  # FoundationModels (test-only duplicate)
]

REMOVE_SECTIONS = [
    "PBXContainerItemProxy",
    "PBXTargetDependency",
]


def remove_pbx_object(text: str, object_id: str) -> str:
    # Only top-level object lines use exactly two leading tabs (not child list refs).
    pattern = re.compile(rf"(?m)^\t\t{re.escape(object_id)} ")
    while True:
        match = pattern.search(text)
        if not match:
            break
        idx = match.start()
        brace = text.find("{", idx)
        if brace == -1:
            break
        depth = 0
        i = brace
        while i < len(text):
            ch = text[i]
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    end = i + 1
                    while end < len(text) and text[end] in " \t":
                        end += 1
                    if end < len(text) and text[end] == ";":
                        end += 1
                    if end < len(text) and text[end] == "\n":
                        end += 1
                    text = text[:idx] + text[end:]
                    break
            i += 1
        else:
            raise RuntimeError(f"unbalanced braces for {object_id}")
    return text


def remove_pbx_section(text: str, section_name: str) -> str:
    begin = f"/* Begin {section_name} section */"
    end = f"/* End {section_name} section */"
    start = text.find(begin)
    if start == -1:
        return text
    stop = text.find(end, start)
    if stop == -1:
        return text
    stop = text.find("\n", stop + len(end))
    if stop != -1:
        stop += 1
    return text[:start] + text[stop:]


def strip_pbxproj(text: str) -> str:
    for oid in REMOVE_OBJECT_IDS:
        text = remove_pbx_object(text, oid)
    for section in REMOVE_SECTIONS:
        text = remove_pbx_section(text, section)

    for line in [
        "\t\t\t\t1C7487722EF688EC00021529 /* CollegeTests */,\n",
        "\t\t\t\t1C74877C2EF688EC00021529 /* CollegeUITests */,\n",
        "\t\t\t\t1C74878F2EF6B53100021529 /* Pages */,\n",
        "\t\t\t\tCC0000012F0D000000000001 /* Config.xcconfig */,\n",
        "\t\t\t\tCC0000022F0D000000000002 /* Secrets.xcconfig.example */,\n",
        "\t\t\t\t1C74876F2EF688EC00021529 /* CollegeTests.xctest */,\n",
        "\t\t\t\t1C7487792EF688EC00021529 /* CollegeUITests.xctest */,\n",
        "\t\t\t\t1C74876E2EF688EC00021529 /* CollegeTests */,\n",
        "\t\t\t\t1C7487782EF688EC00021529 /* CollegeUITests */,\n",
    ]:
        text = text.replace(line, "")

    text = re.sub(
        r"\t\t\t\t1C74878F2EF6B53100021529 /\* Pages \*/,\n",
        "",
        text,
    )

    text = text.replace(
        "\t\t\t\tTargetAttributes = {\n"
        "\t\t\t\t\t1C74875F2EF688EA00021529 = {\n"
        "\t\t\t\t\t\tCreatedOnToolsVersion = 26.2;\n"
        "\t\t\t\t\t};\n"
        "\t\t\t\t\t1C74876E2EF688EC00021529 = {\n"
        "\t\t\t\t\t\tCreatedOnToolsVersion = 26.2;\n"
        "\t\t\t\t\t\tTestTargetID = 1C74875F2EF688EA00021529;\n"
        "\t\t\t\t\t};\n"
        "\t\t\t\t\t1C7487782EF688EC00021529 = {\n"
        "\t\t\t\t\t\tCreatedOnToolsVersion = 26.2;\n"
        "\t\t\t\t\t\tTestTargetID = 1C74875F2EF688EA00021529;\n"
        "\t\t\t\t\t};\n"
        "\t\t\t\t};",
        "\t\t\t\tTargetAttributes = {\n"
        "\t\t\t\t\t1C74875F2EF688EA00021529 = {\n"
        "\t\t\t\t\t\tCreatedOnToolsVersion = 26.2;\n"
        "\t\t\t\t\t};\n"
        "\t\t\t\t};",
    )

    text = re.sub(
        r"\t\t\tbaseConfigurationReference = CC0000012F0D000000000001 /\* Config\.xcconfig \*/;\n",
        "",
        text,
    )
    text = text.replace("buildSettings = {\n", f"buildSettings = {{\n{ARCH_IN_BUILD_SETTINGS}")

    return text


def strip_scheme(text: str) -> str:
    text = re.sub(
        r"<Testables>.*?</Testables>",
        "<Testables/>",
        text,
        flags=re.DOTALL,
    )
    text = text.replace(
        'shouldAutocreateTestPlan = "YES"',
        'shouldAutocreateTestPlan = "NO"',
    )
    return text


def main() -> None:
    pbx = PBX.read_text(encoding="utf-8")
    slimmed = strip_pbxproj(pbx)
    if slimmed.count("{") != slimmed.count("}"):
        raise SystemExit("pbxproj brace mismatch after slim")
    PBX.write_text(slimmed, encoding="utf-8")
    if SCHEME.is_file():
        SCHEME.write_text(
            strip_scheme(SCHEME.read_text(encoding="utf-8")),
            encoding="utf-8",
        )
    print("slimmed", PBX, "and", SCHEME)


if __name__ == "__main__":
    main()
