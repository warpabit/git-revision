import 'dart:async';

import 'package:git_revision/cache.dart';
import 'package:git_revision/git/commit.dart';
import 'package:git_revision/git/git_client.dart';
import 'package:git_revision/git/local_changes.dart';

Duration _YEAR = Duration(days: 365);

class GitVersioner {
  static String DEFAULT_BRANCH = 'master';
  static int DEFAULT_YEAR_FACTOR = 1000;
  static int DEFAULT_STOP_DEBOUNCE = 48;

  final GitVersionerConfig config;
  final GitClient gitClient;

  /// always returns a version which automatically caches
  factory GitVersioner(GitVersionerConfig config) {
    var versioner = GitVersioner._(config, GitClient(config.repoPath));
    return _CachedGitVersioner(versioner);
  }

  GitVersioner._(this.config, this.gitClient);

  Future<int> get revision async {
    var commits = await baseBranchCommits;
    var timeComponent = await baseBranchTimeComponent;
    return commits.length + timeComponent;
  }

  // TODO swap name with revision
  Future<String> get versionName async {
    var rev = await revision;
    var hash = (await gitClient.sha1(config.rev))?.substring(0, 7) ?? "0000000";
    var additionalCommits = await featureBranchCommits;

    if (config.rev == 'HEAD') {
      var branch = await gitClient.headBranchName;
      var changes = await gitClient.localChanges(config.rev);

      String name = '';
      if (branch != null && branch != config.baseBranch) {
        name = branch != null ? "_$branch" : '';
      }
      if (config.name != null && config.name != config.baseBranch) {
        name = "_${config.name}";
      }
      var furtherPart = additionalCommits.isNotEmpty ? "+${additionalCommits.length}" : '';
      var dirtyPart = (changes == LocalChanges.NONE) ? '' : '-dirty';

      return "$rev$name${furtherPart}_$hash$dirtyPart";
    } else {
      var furtherPart = additionalCommits.isNotEmpty ? "+${additionalCommits.length}" : '';
      String name = '';

      if (!hash.startsWith(config.rev) && config.rev != config.baseBranch) {
        name = "_${config.rev}";
      }
      if (config.name != null && config.name != config.baseBranch) {
        name = "_${config.name}";
      }

      return "$rev$name${furtherPart}_$hash";
    }
  }

  /// All first-parent commits in baseBranch
  ///
  /// Most often a subset of [firstHeadBranchCommits]
  Future<List<Commit>> get allFirstBaseBranchCommits async {
    try {
      var base = await gitClient.branchLocalOrRemote(config.baseBranch).first;
      var commits = await gitClient.revList('$base', firstParentOnly: true);
      return commits;
    } catch (ex) {
      return [];
    }
  }

  /// branch name of `HEAD` or `null`
  Future<String> get headBranchName => gitClient.headBranchName;

  /// full Sha1 or `null`
  Future<String> get sha1 => gitClient.sha1(config.rev);

  Future<LocalChanges> get localChanges => gitClient.localChanges(config.rev);

  /// All commits in history of [GitVersionerConfig.rev]
  Future<List<Commit>> get commits => gitClient.revList(config.rev);

  /// Commit where the featureBranch branched off the baseBranch or the first commit in history in case of an
  /// unrelated history
  Future<Commit> get featureBranchOrigin async {
    var firstBaseCommits = await allFirstBaseBranchCommits;
    var allheadCommits = await commits;

    try {
      return allheadCommits.firstWhere((c) => firstBaseCommits.contains(c));
    } catch (ex) {
      return null;
    }
  }

  /// All commits in baseBranch which are also in history of [GitVersionerConfig.rev]
  ///
  /// ignores when current branch is merged into baseBranch in the future. Starts from this commit, first finds
  /// where this branch was branched off the base branch and counts the baseBranch commits from there
  Future<List<Commit>> get baseBranchCommits => featureBranchOrigin.then((origin) {
        if (origin == null) return <Commit>[];
        return gitClient.revList(origin.sha1);
      });

  /// All commits since [GitVersionerConfig.rev] branched off the base branch
  ///
  /// This are the commits which are added to this branch which are not yet merged into baseBranch at this point.
  /// They may be merged already in the future history which will be ignored here
  Future<List<Commit>> get featureBranchCommits async {
    var origin = await featureBranchOrigin;
    if (origin != null) {
      return gitClient.revList('${config.rev}...${origin.sha1}');
    } else {
      // in case of unrelated histories use all commit in history
      return await commits;
    }
  }

  Future<int> get baseBranchTimeComponent => baseBranchCommits.then(_timeComponent);

  Future<int> get featureBranchTimeComponent => featureBranchCommits.then(_timeComponent);

  int _timeComponent(List<Commit> commits) {
    assert(commits != null);
    if (commits.isEmpty) return 0;

    var completeTime = commits.last.date.difference(commits.first.date).abs();
    if (completeTime == Duration.zero) return 0;

    // find gaps
    var gaps = Duration.zero;
    for (var i = 1; i < commits.length; i++) {
      var prev = commits[i];
      // rev-list comes in reversed order
      var next = commits[i - 1];
      var diff = next.date.difference(prev.date).abs();
      if (diff.inHours >= config.stopDebounce) {
        gaps += diff;
      }
    }

    // remove huge gaps where no work happened
    var workingTime = completeTime - gaps;
    var timeComponent = _yearFactor(workingTime);

    return timeComponent;
  }

  int _yearFactor(Duration duration) => (duration.inSeconds * config.yearFactor / _YEAR.inSeconds + 0.5).toInt();
}

class GitVersionerConfig {
  String baseBranch;
  String repoPath;
  int yearFactor;
  int stopDebounce;
  String name;

  /// The revision for which the version should be calculated
  String rev;

  GitVersionerConfig(this.baseBranch, this.repoPath, this.yearFactor, this.stopDebounce, this.name, this.rev)
      : assert(baseBranch != null),
        assert(yearFactor >= 0),
        assert(stopDebounce >= 0),
        assert(rev != null && rev.isNotEmpty);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GitVersionerConfig &&
          runtimeType == other.runtimeType &&
          baseBranch == other.baseBranch &&
          repoPath == other.repoPath &&
          yearFactor == other.yearFactor &&
          stopDebounce == other.stopDebounce &&
          name == other.name &&
          rev == other.rev;

  @override
  int get hashCode =>
      baseBranch.hashCode ^
      repoPath.hashCode ^
      yearFactor.hashCode ^
      stopDebounce.hashCode ^
      name.hashCode ^
      rev.hashCode;
}

/// Caching layer for [GitVersioner]. Caches all futures which never produce a different result (if git repo doesn't change)
class _CachedGitVersioner extends GitVersioner with FutureCacheMixin {
  GitVersioner _delegate;

  _CachedGitVersioner(GitVersioner delegate)
      : _delegate = delegate,
        super._(delegate.config, delegate.gitClient);

  @override
  Future<int> get revision => cache(() => _delegate.revision, 'revision');

  @override
  Future<int> get featureBranchTimeComponent =>
      cache(() => _delegate.featureBranchTimeComponent, 'featureBranchTimeComponent');

  @override
  Future<int> get baseBranchTimeComponent => cache(() => _delegate.baseBranchTimeComponent, 'baseBranchTimeComponent');

  @override
  Future<List<Commit>> get allFirstBaseBranchCommits =>
      cache(() => _delegate.allFirstBaseBranchCommits, 'allFirstBaseBranchCommits');

  @override
  Future<List<Commit>> get featureBranchCommits => cache(() => _delegate.featureBranchCommits, 'featureBranchCommits');

  @override
  Future<List<Commit>> get baseBranchCommits =>
      cache<List<Commit>>(() => _delegate.baseBranchCommits, 'baseBranchCommits');

  @override
  Future<String> get sha1 => cache(() => _delegate.sha1, 'sha1');

  @override
  Future<String> get headBranchName => cache(() => _delegate.headBranchName, 'headBranchName');

  @override
  Future<String> get versionName => cache(() => _delegate.versionName, 'versionName');

  @override
  Future<LocalChanges> get localChanges => cache(() => _delegate.localChanges, 'localChanges');

  @override
  Future<List<Commit>> get commits => cache(() => _delegate.commits, 'commits');

  @override
  Future<Commit> get featureBranchOrigin => cache(() => _delegate.featureBranchOrigin, 'featureBranchOrigin');
}
