"""Remove 'expand' attribute from <group> elements in search views (removed in 18.0)."""
from __future__ import annotations

import re
import typing

if typing.TYPE_CHECKING:
    from odoo.cli.upgrade_code import FileManager


def upgrade(file_manager: FileManager):
    """Remove expand attribute from <group> elements in search views.
    
    In Odoo 18, the 'expand' attribute on <group> elements in search views
    has been removed. Groups are now always collapsed by default.
    
    Examples:
        <group expand="0" string="Group By"> -> <group string="Group By">
        <group expand="1" string="Group By"> -> <group string="Group By">
    """
    
    files = [
        f for f in file_manager
        if f.path.suffix == '.xml'
    ]
    
    if not files:
        return
    
    # Pattern to match expand attribute in <group> tags
    # Matches: expand="0", expand="1", expand='0', expand='1'
    expand_attr_pattern = re.compile(
        r'(<group[^>]*?)\s+expand=["\'][01]["\']([^>]*?>)',
        re.MULTILINE
    )
    
    # Pattern to detect if file contains search views
    search_pattern = re.compile(r'<search')
    
    for fileno, file in enumerate(files, start=1):
        content = file.content
        
        # Only process files with search views
        if not search_pattern.search(content):
            continue
        
        # Remove expand attribute from group tags
        new_content = expand_attr_pattern.sub(r'\1\2', content)
        
        # Only update if content changed (this triggers file listing in dry-run)
        if new_content != content:
            file.content = new_content
        
        file_manager.print_progress(fileno, len(files), file.path)
