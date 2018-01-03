import 'dart:async';

import 'package:git_revision/cli_app.dart';
import 'package:git_revision/git_revision.dart';
import 'package:matcher/matcher.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

void main() {
  group('--help', () {
    MockLogger logger;
    CliApp app;

    setUp(() async {
      logger = new MockLogger();
      app = new CliApp(null /*not required for tests*/, logger);
      await app.process(['--help']);
    });

    test('shows intro text', () async {
      expect(logger.messages.length, 2);
      var helpMessage = logger.messages[0];
      expect(helpMessage, startsWith('Welcome to git revision'));
    });

    test('shows usage information', () async {
      var usageMessage = logger.messages[1];
      expect(usageMessage, contains('baseBranch'));
      expect(usageMessage, contains('format'));
    });

    test('all fields are filled', () async {
      for (var msg in logger.messages) {
        expect(msg, isNot(contains('null')));
      }
    });
  });

  group('help', () {
    test('has exact same output as --help', () async {
      MockLogger logger1 = new MockLogger();
      CliApp app1 = new CliApp(null /*not required for tests*/, logger1);
      await app1.process(['--help']);

      MockLogger logger2 = new MockLogger();
      CliApp app2 = new CliApp(null /*not required for tests*/, logger2);
      await app2.process(['help']);

      expect(logger1.messages, equals(logger2.messages));
      expect(logger1.errors, equals(logger2.errors));
    });
  });

  group('--version', () {
    MockLogger logger;
    CliApp app;

    setUp(() async {
      logger = new MockLogger();
      app = new CliApp(null /*not required for tests*/, logger);
      await app.process(['--version']);
    });

    test('shows version number', () async {
      expect(logger.messages, hasLength(1));
      expect(logger.messages[0], contains('Version'));

      // contains a semantic version string (simplified)
      var semanticVersion = new RegExp(r'.*\d{1,3}\.\d{1,3}\.\d{1,3}.*');
      expect(semanticVersion.hasMatch(logger.messages[0]), true);
    });

    test('all fields are filled', () async {
      for (var msg in logger.messages) {
        expect(msg, isNot(contains('null')));
      }
    });
  });

  group('default - empty args', () {
    MockLogger logger;
    CliApp app;
    GitVersioner versioner;

    setUp(() async {
      logger = new MockLogger();
      versioner = new MockGitVersioner();
      when(versioner.revision()).thenReturn(new Future.value('432'));
      when(versioner.versionName())
          .thenReturn(new Future.value('432-SNAPSHOT'));

      app = new CliApp(versioner, logger);
      await app.process([]);
    });

    test('shows revision', () async {
      expect(logger.messages[0], contains('Revision: 432'));
    });

    test('shows version name', () async {
      expect(logger.messages[0], contains('Version name: 432-SNAPSHOT'));
    });

    test('all fields are filled', () async {
      expect(logger.messages, hasLength(1));
      expect(logger.messages[0], isNot(contains('null')));
    });

    test('requires gitVersioner', () async {
      app = new CliApp(null, new MockLogger());
      try {
        await app.process([]);
      } on ArgumentError catch (e) {
        expect(e.toString(), contains('gitVersioner'));
      }
    });
  });

  group('construct app', () {
    test("logger can't be null", () {
      try {
        new CliApp(null, null);
      } on AssertionError catch (e) {
        expect(e.toString(), contains('logger != null'));
      }
    });
  });
}

class MockGitVersioner extends Mock implements GitVersioner {}

class MockLogger extends CliLogger {
  List<String> messages = [];
  List<String> errors = [];

  @override
  void stdOut(String s) => messages.add(s);

  @override
  void stdErr(String s) => errors.add(s);
}