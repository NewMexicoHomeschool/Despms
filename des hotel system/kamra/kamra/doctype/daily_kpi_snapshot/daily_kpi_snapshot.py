# Copyright (c) 2026, DezPMS and contributors
# For license information, please see license.txt

from frappe.model.document import Document


class DailyKPISnapshot(Document):
	"""One business date's closing figures, written once by the night audit
	(DezPMS.reports.write_kpi_snapshot). Read it with DezPMS.reports.kpi_snapshots."""
