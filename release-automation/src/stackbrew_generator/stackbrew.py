"""Stackbrew library generation."""

from typing import List

from rich.console import Console

from .models import Release, StackbrewEntry

console = Console(stderr=True)


class StackbrewGenerator:
    """Generates stackbrew library content."""

    def generate_tags_for_release(
        self,
        release: Release,
        is_latest: bool = False
    ) -> List[str]:
        """Generate Docker tags for a release.

        Args:
            release: Release to generate tags for
            is_latest: Whether this is the latest version

        Returns:
            List of Docker tags
        """
        tags = []
        version = release.version
        distribution = release.distribution

        # Base version tags
        version_tags = [str(version)]

        # Add mainline version tag only for GA releases (no suffix)
        if not version.is_milestone:
            version_tags.append(version.mainline_version)

        # Add major version tag for latest versions
        if is_latest:
            version_tags.append(str(version.major))

        # For default distribution (Debian), add version tags without distro suffix
        if distribution.is_default:
            tags.extend(version_tags)

        # Add distro-specific tags
        for distro_name in distribution.tag_names:
            for version_tag in version_tags:
                tags.append(f"{version_tag}-{distro_name}")

        # Add special latest tags
        if is_latest:
            if distribution.is_default:
                tags.append("latest")
            # Add bare distro names as tags
            tags.extend(distribution.tag_names)

        return tags

    def generate_stackbrew_library(self, releases: List[Release]) -> List[StackbrewEntry]:
        """Generate stackbrew library entries from releases.

        Args:
            releases: List of releases to process

        Returns:
            List of StackbrewEntry objects
        """
        console.print("[blue]Generating stackbrew library content[/blue]")

        if not releases:
            console.print("[yellow]No releases to process[/yellow]")
            return []

        entries = []
        latest_minor = None
        latest_minor_unset = True

        for release in releases:
            # Determine latest version following bash logic:
            # - Set latest_minor to the minor version of the first non-milestone version
            # - Clear latest_minor if subsequent versions have different minor versions
            if latest_minor_unset:
                if not release.version.is_milestone:
                    latest_minor = release.version.minor
                    latest_minor_unset = False
                    console.print(f"[dim]Latest minor version set to: {latest_minor}[/dim]")
            elif latest_minor != release.version.minor:
                latest_minor = None

            # Check if this release should get latest tags
            is_latest = latest_minor is not None

            # Generate tags for this release
            tags = self.generate_tags_for_release(release, is_latest)

            if tags:
                entry = StackbrewEntry(
                    tags=tags,
                    commit=release.commit,
                    version=release.version,
                    distribution=release.distribution,
                    git_fetch_ref=release.git_fetch_ref
                )
                entries.append(entry)

                console.print(f"[dim]{release.console_repr()} -> {len(tags)} tags[/dim]")
            else:
                console.print(f"[yellow]No tags generated for {release}[/yellow]")

        console.print(f"[green]Generated {len(entries)} stackbrew entries[/green]")
        return entries

    def format_stackbrew_output(self, entries: List[StackbrewEntry]) -> str:
        """Format stackbrew entries as output string.

        Args:
            entries: List of stackbrew entries

        Returns:
            Formatted stackbrew library content
        """
        if not entries:
            return ""

        lines = []
        for i, entry in enumerate(entries):
            if i > 0:
                lines.append("")  # Add blank line between entries
            lines.append(str(entry))

        return "\n".join(lines)
