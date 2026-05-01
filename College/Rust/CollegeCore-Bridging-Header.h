// CollegeCore-Bridging-Header.h
//
// Exposes the Rust college-core C API to Swift.
//
// Setup instructions
// ------------------
// 1. Run:  ./rust-core/build_macos.sh
// 2. In Xcode → College target → Build Settings:
//    - "Objective-C Bridging Header":
//        College/Rust/CollegeCore-Bridging-Header.h
//      (Merge with any existing bridging header if needed.)
//    - "Header Search Paths" (non-recursive):
//        $(SRCROOT)/../rust-core/include
// 3. Add to "Link Binary With Libraries":
//        rust-core/build/libcollege_core.a
// 4. Add compiler flag -DCOLLEGE_CORE_RUST_LINKED to "Other Swift Flags"
//    in the College target's Build Settings (both Debug and Release).
//
// Until step 4 is done, CollegeCoreSwift.swift uses pure-Swift fallbacks
// automatically.

#include "college_core.h"
