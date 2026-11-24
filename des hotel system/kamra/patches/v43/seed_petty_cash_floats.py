"""Backfill per-property petty cash imprest on existing sites."""

import frappe


def execute():
	defaults = {
		"DezPMS Demo Palace": 10000,
		"DezPMS Beach House": 3000,
		"DezPMS Lakeside Villa": 5000,
		"DezPMS Beach Homestay": 2500,
	}
	# Reload Property so petty_cash_float exists before we write it.
	frappe.reload_doc("DezPMS", "doctype", "property")
	for name, amount in defaults.items():
		if not frappe.db.exists("Property", name):
			continue
		if not frappe.db.has_column("Property", "petty_cash_float"):
			continue
		cur = frappe.db.get_value("Property", name, "petty_cash_float")
		if cur in (None, "", 0, 0.0):
			frappe.db.set_value(
				"Property", name, "petty_cash_float", amount, update_modified=False,
			)
