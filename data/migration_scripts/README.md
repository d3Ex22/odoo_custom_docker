# Custom Migration Scripts

This folder contains custom migration scripts for `odoo-bin upgrade_code`.

## How to create a script

Scripts must follow the Odoo upgrade_code format:

1. **File naming**: `{version}-{sequence}-{name}.py`
   - `version`: Target Odoo version (e.g., `19.0`, `18.5`)
   - `sequence`: Execution order (e.g., `00`, `01`, `02`)
   - `name`: Descriptive name in kebab-case

2. **Script structure**:

```python
from __future__ import annotations
import re
import typing

if typing.TYPE_CHECKING:
    from odoo.cli.upgrade_code import FileManager

def upgrade(file_manager: FileManager):
    """Description of what the script does."""
    
    # 1. Filter files
    files = [f for f in file_manager if f.path.suffix == '.py']
    
    if not files:
        return
    
    # 2. Compile regex (once)
    pattern = re.compile(r'old_pattern')
    
    # 3. Process files
    for fileno, file in enumerate(files, start=1):
        content = file.content
        content = pattern.sub('new_pattern', content)
        file.content = content
        file_manager.print_progress(fileno, len(files), file.path)
```

## FileAccessor properties

- `file.path`: Path object (absolute path)
- `file.addon`: Path to the parent Odoo module
- `file.content`: File content (lazy loaded, writable)
- `file.dirty`: True if content was modified

## FileManager methods

- `file_manager.get_file(path)`: Get a specific file
- `file_manager.print_progress(current, total, name)`: Show progress

## Examples

See the example scripts in the `examples/` subfolder:
- `examples/19.0-00-example-rename-field.py` - Rename a field across files
- `examples/19.0-01-example-replace-method.py` - Replace deprecated method calls
- `examples/19.0-02-example-attrs-to-expression.py` - Convert simple attrs

To use an example, copy it to this folder (root level) and modify it.

