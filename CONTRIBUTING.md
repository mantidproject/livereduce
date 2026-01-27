# Contributing to LiveReduce

Thank you for your interest in contributing to LiveReduce! This document provides guidelines for contributing to the project.

## Code of Conduct

Be respectful and constructive in all interactions. We're all working toward better tools for the neutron scattering community.

## Getting Started

### Prerequisites

- Linux system (tested on Fedora/RHEL/CentOS)
- Python 3.9 or later
- [Pixi](https://pixi.sh/) for environment management
- Git for version control

### Setting Up Your Development Environment

1. **Fork and clone the repository:**

```bash
git clone https://github.com/YOUR_USERNAME/livereduce.git
cd livereduce
```

2. **Set up development environment:**

```bash
pixi install
pixi shell
```

This installs:
- Mantid framework
- Python dependencies (pyinotify, psutil)
- Development tools (pre-commit, hatchling)

3. **Install pre-commit hooks:**

```bash
pre-commit install
```

Pre-commit runs linting and formatting checks before each commit.

## Development Workflow

### Making Changes

1. **Create a feature branch:**

```bash
git checkout -b feature/your-feature-name
```

Use descriptive branch names:
- `feature/add-kafka-listener`
- `fix/memory-leak-in-monitor`
- `docs/update-configuration-guide`

2. **Make your changes** following the code style guidelines below.

3. **Test your changes** (see Testing section).

4. **Commit with clear messages:**

```bash
git add .
git commit -m "Add support for Kafka event streaming

- Implement KafkaListener class
- Add configuration options for broker URLs
- Update documentation with Kafka examples"
```

Good commit messages:
- Start with a verb (Add, Fix, Update, Remove)
- Use present tense
- Include "why" context in the body
- Reference issues when applicable

### Code Style

The project uses automated formatting tools:

- **Ruff** for Python linting and formatting
- **Pre-commit** for automated checks

Configuration is in `ruff.toml` and `.pre-commit-config.yaml`.

**Run checks manually:**

```bash
# Run all pre-commit checks
pre-commit run --all-files

# Run ruff directly
pixi run ruff check scripts/ test/
pixi run ruff format scripts/ test/
```

**Python style guidelines:**

- Follow PEP 8
- Use type hints where reasonable
- Keep functions focused and testable
- Add docstrings for public APIs
- Use meaningful variable names

**Example:**

```python
def calculate_memory_usage() -> float:
    """
    Calculate current memory usage as percentage of total system memory.

    Returns:
        Memory usage percentage (0-100).
    """
    memory = psutil.virtual_memory()
    return memory.percent
```

### Testing

#### Local Testing

Test changes using the fake server infrastructure:

```bash
# Terminal 1: Start fake server
python test/fake_server.py

# Terminal 2: Run livereduce with test config
python scripts/livereduce.py test/fake.conf

# Terminal 3: Monitor logs
tail -f livereduce.log
```

**Test different scenarios:**

```bash
# Event data with memory monitoring
python test/fake_event_server.py
python scripts/livereduce.py test/fake_event.conf

# Post-processing only
python scripts/livereduce.py test/postprocessing/fake.conf
```

#### RPM Testing

Test RPM building and installation:

```bash
# Quick spec file validation (runs in CI)
./test/rpm/quick_check.sh

# Full local RPM build and test
./test/rpm/build_and_test.sh

# RPM build in Docker (matches CI environment)
docker build --tag rpmbuilder -f Dockerfile .
```

#### Automated Tests

Before submitting, ensure CI checks will pass:

```bash
# Run pre-commit checks
pre-commit run --all-files

# Build source distribution
pixi run build

# Verify spec file
./test/rpm/quick_check.sh
```

### Submitting Changes

1. **Push your branch:**

```bash
git push origin feature/your-feature-name
```

2. **Create a Pull Request:**

- Go to https://github.com/mantidproject/livereduce
- Click "New Pull Request"
- Select your fork and branch
- Fill out the PR template (see below)

3. **PR Description Template:**

```markdown
## Description
Brief summary of changes and motivation.

## Type of Change
- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to change)
- [ ] Documentation update

## Testing
Describe how you tested your changes:
- [ ] Tested with fake_server.py
- [ ] Tested RPM build
- [ ] Tested on production-like system
- [ ] Added/updated tests

## Checklist
- [ ] Code follows project style guidelines
- [ ] Pre-commit checks pass
- [ ] Documentation updated (if applicable)
- [ ] No new warnings introduced
- [ ] Tested locally

## Related Issues
Fixes #123
```

4. **Respond to review feedback:**

- Address all reviewer comments
- Push additional commits to the same branch
- Request re-review when ready

## Areas for Contribution

### High-Priority Areas

**1. Additional Data Listeners**

Implement support for new data acquisition systems:

```python
class NewFacilityListener:
    """Listener for NewFacility DAE"""

    def connect(self, host: str, port: int):
        """Establish connection to DAE"""
        pass

    def receive_data(self):
        """Receive chunk of live data"""
        pass
```

**2. Memory Management Improvements**

Enhance memory monitoring and recovery:
- Better prediction of memory needs
- Smarter workspace cleanup
- Event data compression strategies

**3. Error Recovery**

Improve resilience to transient failures:
- Automatic reconnection to DAS
- Better handling of network interruptions
- Recovery from corrupted data chunks

**4. Performance Optimization**

Profile and optimize hot paths:
- Reduce latency between chunks
- Optimize workspace operations
- Minimize memory allocations

### Documentation Improvements

Always welcome:
- Fix typos or unclear explanations
- Add examples for specific instruments
- Improve troubleshooting guides
- Add diagrams or visualizations

**Documentation locations:**
- Main guide: `docs/`
- Code documentation: docstrings in `.py` files
- RPM packaging: `test/rpm/README.md`
- Testing: `test/README.md`

### Bug Reports

Found a bug? Please report it:

**Include:**
1. **Description:** What happened vs. what you expected
2. **Steps to reproduce:** Exact sequence to trigger the bug
3. **Environment:**
   - OS and version
   - Mantid version
   - LiveReduce version
   - Configuration file (sanitized)
4. **Logs:** Relevant log excerpts
5. **Impact:** How severe is the issue?

**Example:**

```markdown
## Bug: Memory limit check crashes on systems without swap

**Description:**
LiveReduce crashes with `ZeroDivisionError` on systems without swap space.

**To Reproduce:**
1. Set up system with no swap (`swapoff -a`)
2. Start livereduce with default config
3. Observe crash in logs

**Environment:**
- RHEL 8.5
- Mantid 6.10
- LiveReduce 1.17

**Logs:**
```
Traceback (most recent call last):
  File "livereduce.py", line 234, in check_memory
    swap_percent = swap.total / 100
ZeroDivisionError: division by zero
```

**Impact:** Critical - prevents service from starting
```

## Release Process

(For maintainers)

1. **Update version** in `pyproject.toml`
2. **Update changelog** with notable changes
3. **Tag release:**
   ```bash
   git tag -a v1.18 -m "Release version 1.18"
   git push origin v1.18
   ```
4. **CI builds and tests** automatically
5. **Build RPM** for distribution:
   ```bash
   ./rpmbuild.sh
   ```

## Communication

### Getting Help

- **GitHub Issues:** For bugs and feature requests
- **GitHub Discussions:** For questions and general discussion
- **Pull Request Comments:** For code-specific questions

### Review Process

**What to expect:**

1. **Automated checks** run immediately:
   - Pre-commit hooks
   - RPM spec validation
   - Python build verification
   - RPM build in Docker

2. **Code review** by maintainers:
   - Typically within 1 week
   - May request changes or clarification
   - Constructive feedback on implementation

3. **Approval and merge:**
   - After review approval and passing CI
   - Squash merge preferred for cleaner history
   - Your contribution will be acknowledged!

**Review expectations:**

- Be responsive to feedback
- Keep PRs focused and reasonably sized
- Update documentation alongside code changes
- Maintain backward compatibility when possible

## Architecture Guidelines

### Core Principles

1. **Reliability:** Service must be resilient to failures
2. **Simplicity:** Keep code straightforward and maintainable
3. **Performance:** Minimize latency and resource usage
4. **Observability:** Log useful information for debugging

### Design Patterns

**Config class:**
```python
class Config:
    """
    Encapsulates all configuration.
    Validates on load, provides defaults.
    """
    def __init__(self, filename):
        # Load and validate
        pass

    def toStartLiveArgs(self) -> dict:
        # Convert to algorithm parameters
        pass
```

**LiveDataManager class:**
```python
class LiveDataManager:
    """
    Manages StartLiveData/MonitorLiveData lifecycle.
    Handles start, stop, restart.
    """
    def start(self):
        # Begin monitoring
        pass

    def stop(self):
        # Clean shutdown
        pass
```

**Event handlers:**
```python
class EventHandler(pyinotify.ProcessEvent):
    """
    Watches for file system changes.
    Triggers appropriate actions.
    """
    def process_IN_MODIFY(self, event):
        # React to modification
        pass
```

### Adding New Listeners

To support a new data acquisition system:

1. **Understand the DAS protocol:**
   - Connection method (TCP, HTTP, etc.)
   - Data format (binary, JSON, etc.)
   - Event stream vs. polling

2. **Check if Mantid supports it:**
   - Look in `mantid/Framework/LiveData/`
   - May need Mantid changes first

3. **Add configuration:**
   ```python
   if listener_type == "NewFacilityDAE":
       args["listener"] = "NewFacilityDataListener"
       args["Connection"] = f"{host}:{port}"
   ```

4. **Test thoroughly:**
   - Create test server in `test/`
   - Add test configuration
   - Document in examples

5. **Update documentation:**
   - Add to [Configuration Reference](docs/configuration.md)
   - Add example to [Examples](docs/examples.md)
   - Update [Architecture](docs/architecture.md)

### Code Organization

```
livereduce/
├── scripts/
│   ├── livereduce.py          # Main daemon (keep focused)
│   ├── livereduce.sh           # Wrapper script
│   └── livereduce_watchdog.sh  # Monitoring script
├── test/
│   ├── fake_server.py          # Test infrastructure
│   ├── reduce_*_live_*.py      # Example processing scripts
│   └── rpm/                    # RPM testing
├── docs/
│   └── *.md                    # User/developer documentation
├── livereduce.spec             # RPM packaging
└── pyproject.toml              # Python packaging
```

**Guidelines:**

- Keep `livereduce.py` focused on core logic
- Put complex logic in separate classes
- Test infrastructure goes in `test/`
- Examples should be runnable

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Questions?

Open a GitHub Discussion or reach out to the maintainers. We're here to help!

## Acknowledgments

Thank you for contributing to LiveReduce! Your work helps scientists worldwide get better neutron scattering data.
