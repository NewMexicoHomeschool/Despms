"""The demo reset puts DezPMS Agent back from site_config.json."""

import frappe

from DezPMS.scripts.reset_demo import restore_agent_from_site_config
from DezPMS.tests.audit_fixtures import PROP_A, AuditTestCase, make_property


class DemoAgentKeyTestCase(AuditTestCase):
	properties = (PROP_A,)

	def setUp(self):
		super().setUp()
		make_property(PROP_A)

	def test_agent_comes_back_from_site_config(self):
		frappe.conf.pop("DezPMS_agent_api_key", None)
		self.assertEqual(restore_agent_from_site_config(), 0)
		frappe.conf["DezPMS_agent_api_key"] = "sk-test-not-real"
		try:
			self.assertGreaterEqual(restore_agent_from_site_config(), 1)
			name = frappe.db.get_value("AI Assistant Settings", {"property": PROP_A})
			doc = frappe.get_doc("AI Assistant Settings", name)
			self.assertTrue(doc.enabled)
			self.assertEqual(doc.get_password("api_key"), "sk-test-not-real")
			restore_agent_from_site_config()  # idempotent: updates, no duplicate
			self.assertEqual(frappe.db.count("AI Assistant Settings", {"property": PROP_A}), 1)
		finally:
			frappe.conf.pop("DezPMS_agent_api_key", None)

	def test_reset_keeps_the_agent_settings(self):
		from DezPMS.scripts import reset_demo

		kept = {r.name for r in frappe.get_all(
			"DocType", filters={"module": "DezPMS",
			                    "name": ("not in", list(reset_demo.KEEP_DOCTYPES))})}
		self.assertNotIn("AI Assistant Settings", kept)
		self.assertIn("Reservation", kept)
