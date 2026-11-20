Extract this ZIP to your FYP_New root. The previous 03 installer and commerce_payload folder must already be present.
Run: python .\05_RESUME_COMMERCE_BACKUP_FIRST.py
It stores a byte-perfect copy of conflicting files and a diff under a timestamped BeforeCommerceSafeOverwrite folder outside the project, then runs 03. If 03 fails, the three prepared additions are restored. Existing Git staging is not touched.
