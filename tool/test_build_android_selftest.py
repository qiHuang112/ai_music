import unittest

from build_android_selftest import SELFTEST_FLOOR, next_code


class NextCodeTest(unittest.TestCase):
    def test_starts_at_the_floor_above_formal_releases(self):
        self.assertEqual(next_code([], installed=10283), SELFTEST_FLOOR)

    def test_follows_earlier_builds_and_the_installed_one(self):
        self.assertEqual(next_code([60000, 60004]), 60005)
        self.assertEqual(next_code([60000], installed=60007), 60008)


if __name__ == '__main__':
    unittest.main()
