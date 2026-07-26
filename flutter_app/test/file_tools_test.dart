import 'dart:io';

import 'package:congmiao_toolbox_flutter/core/file_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Dart port of the `file_tools.rs` unit tests plus end-to-end
/// preview → execute → undo flows against real temp directories.
void main() {
  late Directory workDir;
  late Directory journalDir;
  late FileToolsService service;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('congmiao_files');
    journalDir = Directory.systemTemp.createTempSync('congmiao_journal');
    service = FileToolsService(
        journalFile: File(p.join(journalDir.path, 'file-operations.json')));
  });

  tearDown(() {
    for (final dir in [workDir, journalDir]) {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Leftover temp dirs are cleaned by the OS eventually.
      }
    }
  });

  String write(String name, String content) {
    final path = p.join(workDir.path, name);
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
    return path;
  }

  group('rename rules', () {
    test('preserve unicode and extension', () {
      final path = write('照片.JPG', 'image');
      final name = applyRules(
        path,
        0,
        includeExtension: false,
        rules: const [
          PrefixRule('旅行-'),
          SequenceRule(
              start: 1,
              step: 1,
              padding: 3,
              position: 'suffix',
              separator: '_'),
        ],
      );
      expect(name, '旅行-照片_001.JPG');
    });

    test('replace works case-insensitively', () {
      expect(replaceInsensitive('Report-REPORT-report', 'report', 'r'),
          'r-r-r');
      expect(replaceInsensitive('abc', '', 'x'), 'abc');
    });

    test('rejects invalid target names', () {
      expect(filenameError('CON.txt'), isNotNull);
      expect(filenameError('bad?.txt'), isNotNull);
      expect(filenameError('trailing.'), isNotNull);
      expect(filenameError('正常名称.txt'), isNull);
    });
  });

  group('plan building', () {
    test('duplicate targets are invalid', () {
      final a = write('a.txt', 'a');
      final b = write('b.txt', 'b');
      final target = p.join(workDir.path, 'same.txt');
      final plan = debugBuildPlan('rename', [(a, target), (b, target)]);
      expect(plan.invalidCount, 2);
    });

    test('relative folders cannot escape', () {
      expect(() => relativeFolder('../outside'),
          throwsA(isA<FileToolException>()));
      expect(relativeFolder('images/2026'), p.join('images', '2026'));
    });
  });

  group('rename execution', () {
    test('exchange uses temporary names', () {
      final a = write('a.txt', 'A');
      final b = write('b.txt', 'B');
      debugExecuteRenamePairs([(a, b), (b, a)]);
      expect(File(a).readAsStringSync(), 'B');
      expect(File(b).readAsStringSync(), 'A');
    });

    test('preview, execute and undo round-trip', () {
      write('a.txt', 'aaa');
      write('b.txt', 'bbb');
      final plan = service.previewBatchRename(RenamePreviewRequest(
        sourceDir: workDir.path,
        rules: const [PrefixRule('x-')],
      ));
      expect(plan.readyCount, 2);
      expect(plan.invalidCount, 0);

      final record = service.executePlan(plan.planId);
      expect(record.moves.length, 2);
      final root = record.moves.first.targetPath;
      expect(File(p.join(p.dirname(root), 'x-a.txt')).existsSync(), isTrue);
      expect(File(p.join(p.dirname(root), 'x-b.txt')).existsSync(), isTrue);

      // Journal survives across service instances.
      final reopened = FileToolsService(journalFile: service.journalFile);
      final listed = reopened.listOperations();
      expect(listed.single.id, record.id);

      final undone = reopened.undoOperation(record.id);
      expect(undone.undone, isTrue);
      expect(File(p.join(p.dirname(root), 'a.txt')).existsSync(), isTrue);
      expect(File(p.join(p.dirname(root), 'b.txt')).existsSync(), isTrue);
      expect(File(p.join(p.dirname(root), 'x-a.txt')).existsSync(), isFalse);

      expect(() => reopened.undoOperation(record.id),
          throwsA(isA<FileToolException>()));
    });

    test('plans without executable entries are rejected', () {
      write('a.txt', 'aaa');
      final plan = service.previewBatchRename(RenamePreviewRequest(
        sourceDir: workDir.path,
        rules: const [],
      ));
      expect(plan.readyCount, 0);
      expect(() => service.executePlan(plan.planId),
          throwsA(isA<FileToolException>()));
    });

    test('a stale plan id is rejected', () {
      expect(() => service.executePlan('missing'),
          throwsA(isA<FileToolException>()));
    });
  });

  group('organize execution', () {
    test('moves by extension category and undoes', () {
      write('photo.jpg', 'img');
      write('notes.pdf', 'doc');
      final plan = service.previewFileOrganize(OrganizePreviewRequest(
        sourceDir: workDir.path,
        targetDir: workDir.path,
        mode: const OrganizeByExtension(),
      ));
      expect(plan.readyCount, 2);

      final record = service.executePlan(plan.planId);
      final canonicalRoot = p.dirname(p.dirname(record.moves.first.targetPath));
      expect(
          File(p.join(canonicalRoot, '图片', 'photo.jpg')).existsSync(), isTrue);
      expect(
          File(p.join(canonicalRoot, '文档', 'notes.pdf')).existsSync(), isTrue);

      service.undoOperation(record.id);
      expect(File(p.join(canonicalRoot, 'photo.jpg')).existsSync(), isTrue);
      expect(File(p.join(canonicalRoot, 'notes.pdf')).existsSync(), isTrue);
    });

    test('custom mappings override the category', () {
      write('contract.pdf', 'doc');
      final plan = service.previewFileOrganize(OrganizePreviewRequest(
        sourceDir: workDir.path,
        targetDir: workDir.path,
        mode: const OrganizeByExtension(),
        customMappings: const [
          ExtensionMapping(extension: '.PDF', folder: '文档/合同'),
        ],
      ));
      expect(plan.entries.single.targetPath,
          contains(p.join('文档', '合同', 'contract.pdf')));
    });

    test('size thresholds must ascend', () {
      write('a.txt', 'aaa');
      expect(
        () => service.previewFileOrganize(OrganizePreviewRequest(
          sourceDir: workDir.path,
          targetDir: workDir.path,
          mode: const OrganizeBySize(smallBytes: 100, largeBytes: 100),
        )),
        throwsA(isA<FileToolException>()),
      );
    });
  });

  group('duplicate scan', () {
    test('finds identical files through the staged pipeline', () async {
      // 192 KB: head (first 64 KB) and tail (last 64 KB) plus a middle
      // region that only the full hash inspects.
      final base = String.fromCharCodes(
          List.generate(192 * 1024, (i) => 65 + i % 26));
      write('copy1.bin', base);
      write('copy2.bin', base);
      // Same size, differs in the tail → eliminated by the sample stage.
      write('tail_diff.bin',
          base.replaceRange(base.length - 8, base.length, 'ZZZZZZZZ'));
      // Same size, same head/tail, differs in the middle → eliminated only
      // by the full hash stage.
      write('middle_diff.bin',
          base.replaceRange(100 * 1024, 100 * 1024 + 4, 'DIFF'));
      write('small.txt', 'tiny');

      final progressStages = <String>{};
      final job = service.startDuplicateScan(
        DuplicateScanRequest(sourceDir: workDir.path, recursive: true),
        onProgress: (progress) => progressStages.add(progress.stage),
      );
      final result = await job.done;

      expect(result.cancelled, isFalse);
      expect(result.scannedFiles, 5);
      expect(result.groups, hasLength(1));
      final group = result.groups.single;
      expect(group.paths, hasLength(2));
      expect(group.paths.map(p.basename).toSet(), {'copy1.bin', 'copy2.bin'});
      expect(group.reclaimableBytes, group.size);
      expect(result.reclaimableBytes, group.size);
      expect(progressStages, containsAll(<String>{'sample', 'fullHash'}));
    });

    test('cancel stops the job', () async {
      final content = String.fromCharCodes(
          List.generate(256 * 1024, (i) => 97 + i % 26));
      for (var index = 0; index < 6; index++) {
        write('dup_$index.bin', content);
      }
      final job = service.startDuplicateScan(
          DuplicateScanRequest(sourceDir: workDir.path));
      job.cancel();
      final result = await job.done;
      expect(result.cancelled, isTrue);
      expect(result.groups, isEmpty);
    });

    test('zero-byte files are skipped unless included', () async {
      write('empty1.txt', '');
      write('empty2.txt', '');
      final skip = await service
          .startDuplicateScan(DuplicateScanRequest(sourceDir: workDir.path))
          .done;
      expect(skip.groups, isEmpty);
      final include = await service
          .startDuplicateScan(DuplicateScanRequest(
              sourceDir: workDir.path, includeZeroByte: true))
          .done;
      expect(include.groups, hasLength(1));
    });
  });

  test('formatBytes matches the frontend helper', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(2048), '2.0 KB');
    expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
  });
}
