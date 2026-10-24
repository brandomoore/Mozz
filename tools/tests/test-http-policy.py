#!/usr/bin/env python3
"""Check the generated iOS plist and Android policy for self-hosted HTTP."""

import argparse
import plistlib
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
ANDROID = "{http://schemas.android.com/apk/res/android}"


class HTTPPolicyTests(unittest.TestCase):
    def test_ios_allows_http_without_overriding_the_exception(self):
        with self.ios_plist.open("rb") as source:
            info = plistlib.load(source)
        policy = info["NSAppTransportSecurity"]
        self.assertIs(policy.get("NSAllowsArbitraryLoads"), True)
        # The presence of any of these keys disables NSAllowsArbitraryLoads,
        # even if its own value is false, on iOS 10 and later.
        for override in (
            "NSAllowsLocalNetworking",
            "NSAllowsArbitraryLoadsForMedia",
            "NSAllowsArbitraryLoadsInWebContent",
        ):
            self.assertNotIn(override, policy)
        self.assertFalse(policy.get("NSExceptionDomains"))
        self.assertTrue(info.get("NSLocalNetworkUsageDescription"))

    def test_android_allows_http_in_release_and_debug(self):
        manifest = ET.parse(self.android_manifest).getroot()
        application = manifest.find("application")
        self.assertIsNotNone(application)
        self.assertEqual(
            application.get(ANDROID + "networkSecurityConfig"),
            "@xml/network_security_config",
        )
        policy = ET.parse(self.android_config).getroot()
        base = policy.find("base-config")
        self.assertIsNotNone(base)
        self.assertEqual(base.get("cleartextTrafficPermitted"), "true")
        self.assertEqual(policy.findall("domain-config"), [])
        # Leave Android's normal HTTPS certificate trust settings in place.
        self.assertEqual(policy.findall(".//trust-anchors"), [])
        self.assertIsNone(application.get(ANDROID + "usesCleartextTraffic"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--ios-plist", type=Path, default=ROOT / "App/Mozz/Info.plist",
        help="Generated or exported Mozz.app Info.plist; generate the project first.",
    )
    parser.add_argument(
        "--android-manifest", type=Path,
        default=ROOT / "clients/android/app/src/main/AndroidManifest.xml",
        help="Source or merged, text-format Android manifest.",
    )
    parser.add_argument(
        "--android-config", type=Path,
        default=ROOT / "clients/android/app/src/main/res/xml/network_security_config.xml",
        help="Android network-security config.",
    )
    arguments = parser.parse_args()
    HTTPPolicyTests.ios_plist = arguments.ios_plist
    HTTPPolicyTests.android_manifest = arguments.android_manifest
    HTTPPolicyTests.android_config = arguments.android_config
    unittest.main(argv=[__file__])
