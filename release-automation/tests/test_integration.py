"""Integration tests for the stackbrew generator."""

import pytest
from unittest.mock import Mock, patch

from stackbrew_generator.cli import app
from stackbrew_generator.models import RedisVersion, Distribution, DistroType
from typer.testing import CliRunner


class TestIntegration:
    """Integration tests for the complete workflow."""

    def setup_method(self):
        """Set up test fixtures."""
        self.runner = CliRunner()

    @patch('stackbrew_generator.distribution.DistributionDetector')
    @patch('stackbrew_generator.git_operations.GitClient')
    def test_complete_workflow_dry_run(self, mock_git_client_class, mock_distribution_detector_class):
        """Test complete workflow in dry run mode."""
        # Mock git client
        mock_git_client = Mock()
        mock_git_client_class.return_value = mock_git_client

        # Mock distribution detector
        mock_distribution_detector = Mock()
        mock_distribution_detector_class.return_value = mock_distribution_detector

        # Mock git operations
        mock_git_client.list_remote_tags.return_value = [
            ("abc123", "refs/tags/v8.2.1"),
            ("def456", "refs/tags/v8.2.0"),
        ]

        mock_git_client.extract_version_from_tag.side_effect = [
            RedisVersion.parse("8.2.1"),
            RedisVersion.parse("8.2.0"),
        ]

        # Mock releases
        from stackbrew_generator.models import Release, Distribution, DistroType
        mock_releases = [
            Release(
                commit="abc123",
                version=RedisVersion.parse("8.2.1"),
                distribution=Distribution(type=DistroType.DEBIAN, name="bookworm"),
                git_fetch_ref="refs/tags/v8.2.1"
            )
        ]
        mock_distribution_detector.prepare_releases_list.return_value = mock_releases

        # Run command in dry run mode
        result = self.runner.invoke(app, ["generate", "8", "--dry-run", "--verbose"])

        # Check that it completed successfully
        assert result.exit_code == 0
        assert "DRY RUN: Would generate stackbrew library" in result.stderr
        assert "Generated content:" in result.stderr

    def test_version_command(self):
        """Test version command."""
        result = self.runner.invoke(app, ["version"])
        assert result.exit_code == 0
        assert "stackbrew-library-generator" in result.stderr

    def test_invalid_major_version(self):
        """Test handling of invalid major version."""
        result = self.runner.invoke(app, ["generate", "0"])
        assert result.exit_code != 0

    @patch('stackbrew_generator.git_operations.GitClient')
    def test_no_tags_found(self, mock_git_client_class):
        """Test handling when no tags are found."""
        # Mock git client to return no tags
        mock_git_client = Mock()
        mock_git_client_class.return_value = mock_git_client
        mock_git_client.list_remote_tags.return_value = []

        result = self.runner.invoke(app, ["generate", "99"])
        assert result.exit_code == 1
        assert "No tags found" in result.stderr

    @patch('stackbrew_generator.version_filter.VersionFilter.get_actual_major_redis_versions')
    def test_no_versions_found(self, mock_get_versions):
        """Test handling when no versions are found."""
        # Mock git client to return no tags
        mock_get_versions.return_value = []

        result = self.runner.invoke(app, ["generate", "8"])
        #assert result.exit_code == 1
        assert "No versions found" in result.stderr

    def test_help_output(self):
        """Test help output."""
        result = self.runner.invoke(app, ["generate", "--help"])
        assert result.exit_code == 0
        assert "Generate stackbrew library content" in result.stdout
        assert "--remote" in result.stdout
        assert "--verbose" in result.stdout
        assert "--dry-run" in result.stdout
