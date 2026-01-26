import re

html = open("search_page.html", "r").read()

# Strategy 1: Dropdown
pattern1 = r"<select[^>]+name=\"filter\[keyword\]\"[^>]*>([\s\S]*?)</select>"
match1 = re.search(pattern1, html, re.IGNORECASE)
if match1:
    print("Strategy 1: Found dropdown")
    content = match1.group(1)
    # print(content)
else:
    print("Strategy 1: Dropdown NOT found")

# Strategy 2: Prefix List
# Swift Regex: <span class=['\"].prefix_box_list['\"]>([A-Z]{2,4})
# Python Regex needs to be similar
pattern2 = r"<span class=['\"].prefix_box_list['\"]>([A-Z]{2,4})"
matches2 = re.findall(pattern2, html)

print(f"Strategy 2: Found {len(matches2)} matches")
if matches2:
    print("Sample matches:", matches2[:5])

# Check specific match for CSE
if "CSE" in matches2:
    print("Found CSE in matches")
else:
    print("CSE NOT found in matches")
