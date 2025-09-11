"""CLI interface for stackbrew library generator."""

import typer
from rich.console import Console
from rich.traceback import install

from .distribution import DistributionDetector
from .exceptions import StackbrewGeneratorError
from .git_operations import GitClient
from .logging_config import setup_logging
from .stackbrew import StackbrewGenerator
from .version_filter import VersionFilter

# Install rich traceback handler
install(show_locals=True)

app = typer.Typer(
    name="release-automation",
    help="Generate stackbrew library content for Redis Docker images",
    add_completion=False,
)

# Console for logging and user messages (stderr)
console = Console(stderr=True)


@app.command()
def generate(
    major_version: int = typer.Argument(
        ...,
        help="Redis major version to process (e.g., 8 for Redis 8.x)"
    ),
    remote: str = typer.Option(
        "origin",
        "--remote",
        help="Git remote to use for fetching tags and branches"
    ),
    verbose: bool = typer.Option(
        False,
        "--verbose",
        "-v",
        help="Enable verbose output"
    ),
    dry_run: bool = typer.Option(
        False,
        "--dry-run",
        help="Show generated content without outputting to stdout"
    ),
) -> None:
    """Generate stackbrew library content for Redis Docker images.

    This command:
    1. Fetches Redis version tags from the specified remote
    2. Filters versions to remove EOL and select latest patches
    3. Extracts distribution information from Dockerfiles
    4. Generates appropriate Docker tags for each version/distribution
    5. Outputs stackbrew library content
    """
    # Set up logging
    setup_logging(verbose=verbose, console=console)

    if verbose:
        console.print(f"[bold blue]Stackbrew Library Generator[/bold blue]")
        console.print(f"Major version: {major_version}")
        console.print(f"Remote: {remote}")
        if dry_run:
            console.print("[yellow]DRY RUN MODE - Generated content will be shown but not output to stdout[/yellow]")

    try:
        # Initialize components
        git_client = GitClient(remote=remote)
        version_filter = VersionFilter(git_client)
        distribution_detector = DistributionDetector(git_client)
        stackbrew_generator = StackbrewGenerator()

        # Get actual Redis versions to process
        versions = version_filter.get_actual_major_redis_versions(major_version)

        if not versions:
            console.print(f"[red]No versions found for Redis {major_version}.x[/red]")
            raise typer.Exit(1)

        # Fetch required refs
        refs_to_fetch = [commit for _, commit, _ in versions]
        git_client.fetch_refs(refs_to_fetch)

        # Prepare releases list with distribution information
        releases = distribution_detector.prepare_releases_list(versions)

        if not releases:
            console.print("[red]No releases prepared[/red]")
            raise typer.Exit(1)

        # Generate stackbrew library content
        entries = stackbrew_generator.generate_stackbrew_library(releases)
        output = stackbrew_generator.format_stackbrew_output(entries)

        if dry_run:
            console.print(f"[yellow]DRY RUN: Would generate stackbrew library with {len(entries)} entries[/yellow]")
            if verbose:
                console.print("[yellow]Generated content:[/yellow]")
                console.print(output)
        else:
            if output:
                # Output the stackbrew library content
                print(output)

                if verbose:
                    console.print(f"[green]Generated stackbrew library with {len(entries)} entries[/green]")
            else:
                console.print("[yellow]No stackbrew content generated[/yellow]")

    except StackbrewGeneratorError as e:
        if verbose and hasattr(e, 'get_detailed_message'):
            console.print(f"[red]{e.get_detailed_message()}[/red]")
        else:
            console.print(f"[red]Error: {e}[/red]")
        if verbose:
            console.print_exception()
        raise typer.Exit(1)
    except KeyboardInterrupt:
        console.print("\n[yellow]Operation cancelled by user[/yellow]")
        raise typer.Exit(130)
    except Exception as e:
        console.print(f"[red]Unexpected error: {e}[/red]")
        if verbose:
            console.print_exception()
        raise typer.Exit(1)


@app.command()
def version() -> None:
    """Show version information."""
    from . import __version__
    console.print(f"stackbrew-library-generator {__version__}")


if __name__ == "__main__":
    app()
