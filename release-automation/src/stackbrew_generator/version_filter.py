"""Version filtering and processing for Redis releases."""

from typing import Dict, List, Tuple

from packaging.version import Version
from rich.console import Console

from .git_operations import GitClient
from .models import RedisVersion

console = Console(stderr=True)


class VersionFilter:
    """Filters and processes Redis versions."""

    def __init__(self, git_client: GitClient):
        """Initialize version filter.

        Args:
            git_client: Git client for operations
        """
        self.git_client = git_client

    def get_redis_versions_from_tags(self, major_version: int) -> List[Tuple[RedisVersion, str]]:
        """Get Redis versions from git tags.

        Args:
            major_version: Major version to filter for

        Returns:
            List of (RedisVersion, commit) tuples sorted by version (newest first)
        """
        console.print(f"[blue]Getting Redis versions for major version {major_version}[/blue]")

        # Get remote tags
        tags = self.git_client.list_remote_tags(major_version)

        # Parse versions from tags
        versions = []
        for commit, tag_ref in tags:
            try:
                version = self.git_client.extract_version_from_tag(tag_ref, major_version)
                versions.append((version, commit))
            except Exception as e:
                console.print(f"[yellow]Warning: Skipping invalid tag {tag_ref}: {e}[/yellow]")
                continue

        # Sort by version (newest first)
        versions.sort(key=lambda x: x[0], reverse=True)

        console.print(f"[dim]Parsed {len(versions)} valid versions[/dim]")
        return versions

    def filter_eol_versions(self, versions: List[Tuple[RedisVersion, str]]) -> List[Tuple[RedisVersion, str]]:
        """Filter out end-of-life versions.

        Args:
            versions: List of (RedisVersion, commit) tuples

        Returns:
            Filtered list with EOL minor versions removed
        """
        console.print("[blue]Filtering out EOL versions[/blue]")

        # Group versions by minor version
        minor_versions: Dict[str, List[Tuple[RedisVersion, str]]] = {}
        for version, commit in versions:
            minor_key = version.mainline_version
            if minor_key not in minor_versions:
                minor_versions[minor_key] = []
            minor_versions[minor_key].append((version, commit))

        # Check each minor version for EOL marker
        filtered_versions = []
        for minor_key, minor_group in minor_versions.items():
            # Check if any version in this minor series is marked as EOL
            has_eol = any(version.is_eol for version, _ in minor_group)

            if has_eol:
                console.print(f"[yellow]Skipping minor version {minor_key}.* due to EOL[/yellow]")
            else:
                filtered_versions.extend(minor_group)

        # Sort again after filtering
        filtered_versions.sort(key=lambda x: x[0], reverse=True)

        console.print(f"[dim]Kept {len(filtered_versions)} versions after EOL filtering[/dim]")
        return filtered_versions

    def filter_actual_versions(self, versions: List[Tuple[RedisVersion, str]]) -> List[Tuple[RedisVersion, str]]:
        """Filter to keep only the latest patch version for each minor version and milestone status.

        Args:
            versions: List of (RedisVersion, commit) tuples (should be sorted newest first)

        Returns:
            Filtered list with only the latest versions for each minor/milestone combination
        """
        console.print("[blue]Filtering to actual versions (latest patch per minor/milestone)[/blue]")

        seen_combinations = set()
        filtered_versions = []

        for version, commit in versions:
            # Create a key for minor version + milestone status
            combination_key = (version.mainline_version, version.is_milestone)

            if combination_key not in seen_combinations:
                seen_combinations.add(combination_key)
                filtered_versions.append((version, commit))

                milestone_str = "milestone" if version.is_milestone else "GA"
                console.print(f"[dim]Selected [bold yellow]{version}[/bold yellow] ({milestone_str}) - {commit[:8]}[/dim]")
            else:
                milestone_str = "milestone" if version.is_milestone else "GA"
                console.print(f"[dim]Skipping {version} ({milestone_str}) - already have this minor/milestone combination[/dim]")

        console.print(f"[dim]Selected {len(filtered_versions)} actual versions[/dim]")
        return filtered_versions

    def get_actual_major_redis_versions(self, major_version: int) -> List[Tuple[RedisVersion, str]]:
        """Get the actual Redis versions to process for a major version.

        This is the main entry point that combines all filtering steps:
        1. Get versions from git tags
        2. Filter out EOL versions
        3. Filter to actual versions (latest patch per minor/milestone)

        Args:
            major_version: Major version to process

        Returns:
            List of (RedisVersion, commit) tuples for processing
        """
        console.print(f"[bold blue]Processing Redis {major_version}.x versions[/bold blue]")

        # Get all versions from tags
        versions = self.get_redis_versions_from_tags(major_version)

        if not versions:
            console.print(f"[red]No versions found for major version {major_version}[/red]")
            return []

        # Apply filters
        versions = self.filter_eol_versions(versions)
        versions = self.filter_actual_versions(versions)

        console.print(f"[green]Final selection: {len(versions)} versions to process[/green]")
        for version, commit in versions:
            console.print(f"[green]  [bold yellow]{version}[/bold yellow] - {commit[:8]}[/green]")

        return versions
