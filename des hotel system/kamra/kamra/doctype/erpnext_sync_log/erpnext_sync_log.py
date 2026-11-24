# Copyright (c) 2026, DezPMS and contributors
# For license information, please see license.txt

from frappe.model.document import Document


class ERPNextSyncLog(Document):
	"""What DezPMS posted to ERPNext, one row per business date, supplier
	bill or supplier payment: DezPMS.erpnext_bridge keys on it so nothing
	posts twice."""
