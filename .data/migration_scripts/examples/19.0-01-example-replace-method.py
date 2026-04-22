# Example: Replace deprecated method calls
# This script replaces 'old_method()' with 'new_method()' in Python files
#
# To use: Copy this file, rename it, and modify the patterns below

from __future__ import annotations

import re
import typing

if typing.TYPE_CHECKING:
    from odoo.cli.upgrade_code import FileManager


# Configuration - modify these values
REPLACEMENTS = [
    # (old_pattern, new_pattern)
    (r'\.old_method\(\)', '.new_method()'),
    (r'self\.deprecated_call\(([^)]*)\)', r'self.modern_call(\1)'),
]


def upgrade(file_manager: FileManager):
    """Replace deprecated method calls with modern equivalents."""
    
    # Filter Python files only
    files = [
        f for f in file_manager
        if f.path.suffix == '.py'
        if 'models' in f.path.parts or 'wizards' in f.path.parts
    ]
    
    if not files:
        return
    
    # Compile all patterns
    patterns = [(re.compile(old), new) for old, new in REPLACEMENTS]
    
    for fileno, file in enumerate(files, start=1):
        content = file.content
        
        for pattern, replacement in patterns:
            content = pattern.sub(replacement, content)
        
        file.content = content
        file_manager.print_progress(fileno, len(files), file.path)

