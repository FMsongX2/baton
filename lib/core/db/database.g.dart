// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $NodesTable extends Nodes with TableInfo<$NodesTable, Node> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'),
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta('parentId');
  @override
  late final GeneratedColumn<int> parentId = GeneratedColumn<int>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('REFERENCES nodes (id)'),
  );
  @override
  late final GeneratedColumnWithTypeConverter<NodeKind, String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<NodeKind>($NodesTable.$converterkind);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 200),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortIndexMeta = const VerificationMeta('sortIndex');
  @override
  late final GeneratedColumn<int> sortIndex = GeneratedColumn<int>(
    'sort_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    parentId,
    kind,
    name,
    sortIndex,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'nodes';
  @override
  VerificationContext validateIntegrity(Insertable<Node> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(_nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_index')) {
      context.handle(
        _sortIndexMeta,
        sortIndex.isAcceptableOrUnknown(data['sort_index']!, _sortIndexMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Node map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Node(
      id: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parent_id'],
      ),
      kind: $NodesTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      ),
      name: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      sortIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_index'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $NodesTable createAlias(String alias) {
    return $NodesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<NodeKind, String, String> $converterkind =
      const EnumNameConverter<NodeKind>(NodeKind.values);
}

class Node extends DataClass implements Insertable<Node> {
  final int id;
  final int? parentId;
  final NodeKind kind;
  final String name;
  final int sortIndex;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// null이 아니면 휴지통에 있음. 실제 파일은 이 시점에 지우지 않음.
  final DateTime? deletedAt;
  const Node({
    required this.id,
    this.parentId,
    required this.kind,
    required this.name,
    required this.sortIndex,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<int>(parentId);
    }
    {
      map['kind'] = Variable<String>($NodesTable.$converterkind.toSql(kind));
    }
    map['name'] = Variable<String>(name);
    map['sort_index'] = Variable<int>(sortIndex);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  NodesCompanion toCompanion(bool nullToAbsent) {
    return NodesCompanion(
      id: Value(id),
      parentId: parentId == null && nullToAbsent ? const Value.absent() : Value(parentId),
      kind: Value(kind),
      name: Value(name),
      sortIndex: Value(sortIndex),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent ? const Value.absent() : Value(deletedAt),
    );
  }

  factory Node.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Node(
      id: serializer.fromJson<int>(json['id']),
      parentId: serializer.fromJson<int?>(json['parentId']),
      kind: $NodesTable.$converterkind.fromJson(serializer.fromJson<String>(json['kind'])),
      name: serializer.fromJson<String>(json['name']),
      sortIndex: serializer.fromJson<int>(json['sortIndex']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'parentId': serializer.toJson<int?>(parentId),
      'kind': serializer.toJson<String>($NodesTable.$converterkind.toJson(kind)),
      'name': serializer.toJson<String>(name),
      'sortIndex': serializer.toJson<int>(sortIndex),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  Node copyWith({
    int? id,
    Value<int?> parentId = const Value.absent(),
    NodeKind? kind,
    String? name,
    int? sortIndex,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => Node(
    id: id ?? this.id,
    parentId: parentId.present ? parentId.value : this.parentId,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    sortIndex: sortIndex ?? this.sortIndex,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  Node copyWithCompanion(NodesCompanion data) {
    return Node(
      id: data.id.present ? data.id.value : this.id,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      kind: data.kind.present ? data.kind.value : this.kind,
      name: data.name.present ? data.name.value : this.name,
      sortIndex: data.sortIndex.present ? data.sortIndex.value : this.sortIndex,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Node(')
          ..write('id: $id, ')
          ..write('parentId: $parentId, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('sortIndex: $sortIndex, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, parentId, kind, name, sortIndex, createdAt, updatedAt, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Node &&
          other.id == this.id &&
          other.parentId == this.parentId &&
          other.kind == this.kind &&
          other.name == this.name &&
          other.sortIndex == this.sortIndex &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class NodesCompanion extends UpdateCompanion<Node> {
  final Value<int> id;
  final Value<int?> parentId;
  final Value<NodeKind> kind;
  final Value<String> name;
  final Value<int> sortIndex;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  const NodesCompanion({
    this.id = const Value.absent(),
    this.parentId = const Value.absent(),
    this.kind = const Value.absent(),
    this.name = const Value.absent(),
    this.sortIndex = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
  });
  NodesCompanion.insert({
    this.id = const Value.absent(),
    this.parentId = const Value.absent(),
    required NodeKind kind,
    required String name,
    this.sortIndex = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
  }) : kind = Value(kind),
       name = Value(name);
  static Insertable<Node> custom({
    Expression<int>? id,
    Expression<int>? parentId,
    Expression<String>? kind,
    Expression<String>? name,
    Expression<int>? sortIndex,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (parentId != null) 'parent_id': parentId,
      if (kind != null) 'kind': kind,
      if (name != null) 'name': name,
      if (sortIndex != null) 'sort_index': sortIndex,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
    });
  }

  NodesCompanion copyWith({
    Value<int>? id,
    Value<int?>? parentId,
    Value<NodeKind>? kind,
    Value<String>? name,
    Value<int>? sortIndex,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
  }) {
    return NodesCompanion(
      id: id ?? this.id,
      parentId: parentId ?? this.parentId,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      sortIndex: sortIndex ?? this.sortIndex,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<int>(parentId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>($NodesTable.$converterkind.toSql(kind.value));
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortIndex.present) {
      map['sort_index'] = Variable<int>(sortIndex.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NodesCompanion(')
          ..write('id: $id, ')
          ..write('parentId: $parentId, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('sortIndex: $sortIndex, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }
}

class $ScoresTable extends Scores with TableInfo<$ScoresTable, Score> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScoresTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nodeIdMeta = const VerificationMeta('nodeId');
  @override
  late final GeneratedColumn<int> nodeId = GeneratedColumn<int>(
    'node_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES nodes (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _fileRelMeta = const VerificationMeta('fileRel');
  @override
  late final GeneratedColumn<String> fileRel = GeneratedColumn<String>(
    'file_rel',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pageCountMeta = const VerificationMeta('pageCount');
  @override
  late final GeneratedColumn<int> pageCount = GeneratedColumn<int>(
    'page_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bpmMeta = const VerificationMeta('bpm');
  @override
  late final GeneratedColumn<double> bpm = GeneratedColumn<double>(
    'bpm',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(120),
  );
  static const VerificationMeta _timeSigNumMeta = const VerificationMeta('timeSigNum');
  @override
  late final GeneratedColumn<int> timeSigNum = GeneratedColumn<int>(
    'time_sig_num',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(4),
  );
  static const VerificationMeta _timeSigDenMeta = const VerificationMeta('timeSigDen');
  @override
  late final GeneratedColumn<int> timeSigDen = GeneratedColumn<int>(
    'time_sig_den',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(4),
  );
  static const VerificationMeta _clicksPerBarMeta = const VerificationMeta('clicksPerBar');
  @override
  late final GeneratedColumn<int> clicksPerBar = GeneratedColumn<int>(
    'clicks_per_bar',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(4),
  );
  static const VerificationMeta _countInBarsMeta = const VerificationMeta('countInBars');
  @override
  late final GeneratedColumn<int> countInBars = GeneratedColumn<int>(
    'count_in_bars',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _leadBeatsMeta = const VerificationMeta('leadBeats');
  @override
  late final GeneratedColumn<double> leadBeats = GeneratedColumn<double>(
    'lead_beats',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(2),
  );
  static const VerificationMeta _pageOrderJsonMeta = const VerificationMeta('pageOrderJson');
  @override
  late final GeneratedColumn<String> pageOrderJson = GeneratedColumn<String>(
    'page_order_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _playOrderJsonMeta = const VerificationMeta('playOrderJson');
  @override
  late final GeneratedColumn<String> playOrderJson = GeneratedColumn<String>(
    'play_order_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _composerMeta = const VerificationMeta('composer');
  @override
  late final GeneratedColumn<String> composer = GeneratedColumn<String>(
    'composer',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _memoMeta = const VerificationMeta('memo');
  @override
  late final GeneratedColumn<String> memo = GeneratedColumn<String>(
    'memo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    nodeId,
    fileRel,
    pageCount,
    bpm,
    timeSigNum,
    timeSigDen,
    clicksPerBar,
    countInBars,
    leadBeats,
    pageOrderJson,
    playOrderJson,
    composer,
    memo,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scores';
  @override
  VerificationContext validateIntegrity(Insertable<Score> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('node_id')) {
      context.handle(_nodeIdMeta, nodeId.isAcceptableOrUnknown(data['node_id']!, _nodeIdMeta));
    }
    if (data.containsKey('file_rel')) {
      context.handle(_fileRelMeta, fileRel.isAcceptableOrUnknown(data['file_rel']!, _fileRelMeta));
    } else if (isInserting) {
      context.missing(_fileRelMeta);
    }
    if (data.containsKey('page_count')) {
      context.handle(
        _pageCountMeta,
        pageCount.isAcceptableOrUnknown(data['page_count']!, _pageCountMeta),
      );
    } else if (isInserting) {
      context.missing(_pageCountMeta);
    }
    if (data.containsKey('bpm')) {
      context.handle(_bpmMeta, bpm.isAcceptableOrUnknown(data['bpm']!, _bpmMeta));
    }
    if (data.containsKey('time_sig_num')) {
      context.handle(
        _timeSigNumMeta,
        timeSigNum.isAcceptableOrUnknown(data['time_sig_num']!, _timeSigNumMeta),
      );
    }
    if (data.containsKey('time_sig_den')) {
      context.handle(
        _timeSigDenMeta,
        timeSigDen.isAcceptableOrUnknown(data['time_sig_den']!, _timeSigDenMeta),
      );
    }
    if (data.containsKey('clicks_per_bar')) {
      context.handle(
        _clicksPerBarMeta,
        clicksPerBar.isAcceptableOrUnknown(data['clicks_per_bar']!, _clicksPerBarMeta),
      );
    }
    if (data.containsKey('count_in_bars')) {
      context.handle(
        _countInBarsMeta,
        countInBars.isAcceptableOrUnknown(data['count_in_bars']!, _countInBarsMeta),
      );
    }
    if (data.containsKey('lead_beats')) {
      context.handle(
        _leadBeatsMeta,
        leadBeats.isAcceptableOrUnknown(data['lead_beats']!, _leadBeatsMeta),
      );
    }
    if (data.containsKey('page_order_json')) {
      context.handle(
        _pageOrderJsonMeta,
        pageOrderJson.isAcceptableOrUnknown(data['page_order_json']!, _pageOrderJsonMeta),
      );
    }
    if (data.containsKey('play_order_json')) {
      context.handle(
        _playOrderJsonMeta,
        playOrderJson.isAcceptableOrUnknown(data['play_order_json']!, _playOrderJsonMeta),
      );
    }
    if (data.containsKey('composer')) {
      context.handle(
        _composerMeta,
        composer.isAcceptableOrUnknown(data['composer']!, _composerMeta),
      );
    }
    if (data.containsKey('memo')) {
      context.handle(_memoMeta, memo.isAcceptableOrUnknown(data['memo']!, _memoMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {nodeId};
  @override
  Score map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Score(
      nodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}node_id'],
      )!,
      fileRel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_rel'],
      )!,
      pageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_count'],
      )!,
      bpm: attachedDatabase.typeMapping.read(DriftSqlType.double, data['${effectivePrefix}bpm'])!,
      timeSigNum: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}time_sig_num'],
      )!,
      timeSigDen: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}time_sig_den'],
      )!,
      clicksPerBar: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}clicks_per_bar'],
      )!,
      countInBars: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}count_in_bars'],
      )!,
      leadBeats: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lead_beats'],
      )!,
      pageOrderJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}page_order_json'],
      ),
      playOrderJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}play_order_json'],
      ),
      composer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}composer'],
      ),
      memo: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}memo']),
    );
  }

  @override
  $ScoresTable createAlias(String alias) {
    return $ScoresTable(attachedDatabase, alias);
  }
}

class Score extends DataClass implements Insertable<Score> {
  final int nodeId;

  /// `scores/<nodeId>/source.pdf` 형태의 상대경로.
  final String fileRel;
  final int pageCount;
  final double bpm;
  final int timeSigNum;
  final int timeSigDen;

  /// 마디당 클릭 수. 겹박자를 별도 분기 없이 처리하려고 박자표와 분리해 둠.
  final int clicksPerBar;
  final int countInBars;

  /// 페이지를 몇 박 일찍 넘길지. 연주자가 다음 줄을 미리 읽을 여유.
  final double leadBeats;

  /// 화면에 보여줄 페이지의 순서. 물리 페이지 인덱스 배열 JSON이며 중복은 없음.
  /// 여기서 빠진 페이지는 숨겨진 것으로 봄. PDF 자체는 건드리지 않아 필기가 그대로 따라옴.
  /// null이면 0..pageCount-1 순서 그대로.
  final String? pageOrderJson;

  /// 재생 순서. pageOrder상의 위치를 가리키는 인덱스 배열 JSON이며 중복을 허용함.
  /// 페이지 단위 반복·D.S.·D.C.를 전부 이 배열로 펼쳐서 표현함. null이면 선형.
  final String? playOrderJson;
  final String? composer;
  final String? memo;
  const Score({
    required this.nodeId,
    required this.fileRel,
    required this.pageCount,
    required this.bpm,
    required this.timeSigNum,
    required this.timeSigDen,
    required this.clicksPerBar,
    required this.countInBars,
    required this.leadBeats,
    this.pageOrderJson,
    this.playOrderJson,
    this.composer,
    this.memo,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['node_id'] = Variable<int>(nodeId);
    map['file_rel'] = Variable<String>(fileRel);
    map['page_count'] = Variable<int>(pageCount);
    map['bpm'] = Variable<double>(bpm);
    map['time_sig_num'] = Variable<int>(timeSigNum);
    map['time_sig_den'] = Variable<int>(timeSigDen);
    map['clicks_per_bar'] = Variable<int>(clicksPerBar);
    map['count_in_bars'] = Variable<int>(countInBars);
    map['lead_beats'] = Variable<double>(leadBeats);
    if (!nullToAbsent || pageOrderJson != null) {
      map['page_order_json'] = Variable<String>(pageOrderJson);
    }
    if (!nullToAbsent || playOrderJson != null) {
      map['play_order_json'] = Variable<String>(playOrderJson);
    }
    if (!nullToAbsent || composer != null) {
      map['composer'] = Variable<String>(composer);
    }
    if (!nullToAbsent || memo != null) {
      map['memo'] = Variable<String>(memo);
    }
    return map;
  }

  ScoresCompanion toCompanion(bool nullToAbsent) {
    return ScoresCompanion(
      nodeId: Value(nodeId),
      fileRel: Value(fileRel),
      pageCount: Value(pageCount),
      bpm: Value(bpm),
      timeSigNum: Value(timeSigNum),
      timeSigDen: Value(timeSigDen),
      clicksPerBar: Value(clicksPerBar),
      countInBars: Value(countInBars),
      leadBeats: Value(leadBeats),
      pageOrderJson: pageOrderJson == null && nullToAbsent
          ? const Value.absent()
          : Value(pageOrderJson),
      playOrderJson: playOrderJson == null && nullToAbsent
          ? const Value.absent()
          : Value(playOrderJson),
      composer: composer == null && nullToAbsent ? const Value.absent() : Value(composer),
      memo: memo == null && nullToAbsent ? const Value.absent() : Value(memo),
    );
  }

  factory Score.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Score(
      nodeId: serializer.fromJson<int>(json['nodeId']),
      fileRel: serializer.fromJson<String>(json['fileRel']),
      pageCount: serializer.fromJson<int>(json['pageCount']),
      bpm: serializer.fromJson<double>(json['bpm']),
      timeSigNum: serializer.fromJson<int>(json['timeSigNum']),
      timeSigDen: serializer.fromJson<int>(json['timeSigDen']),
      clicksPerBar: serializer.fromJson<int>(json['clicksPerBar']),
      countInBars: serializer.fromJson<int>(json['countInBars']),
      leadBeats: serializer.fromJson<double>(json['leadBeats']),
      pageOrderJson: serializer.fromJson<String?>(json['pageOrderJson']),
      playOrderJson: serializer.fromJson<String?>(json['playOrderJson']),
      composer: serializer.fromJson<String?>(json['composer']),
      memo: serializer.fromJson<String?>(json['memo']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'nodeId': serializer.toJson<int>(nodeId),
      'fileRel': serializer.toJson<String>(fileRel),
      'pageCount': serializer.toJson<int>(pageCount),
      'bpm': serializer.toJson<double>(bpm),
      'timeSigNum': serializer.toJson<int>(timeSigNum),
      'timeSigDen': serializer.toJson<int>(timeSigDen),
      'clicksPerBar': serializer.toJson<int>(clicksPerBar),
      'countInBars': serializer.toJson<int>(countInBars),
      'leadBeats': serializer.toJson<double>(leadBeats),
      'pageOrderJson': serializer.toJson<String?>(pageOrderJson),
      'playOrderJson': serializer.toJson<String?>(playOrderJson),
      'composer': serializer.toJson<String?>(composer),
      'memo': serializer.toJson<String?>(memo),
    };
  }

  Score copyWith({
    int? nodeId,
    String? fileRel,
    int? pageCount,
    double? bpm,
    int? timeSigNum,
    int? timeSigDen,
    int? clicksPerBar,
    int? countInBars,
    double? leadBeats,
    Value<String?> pageOrderJson = const Value.absent(),
    Value<String?> playOrderJson = const Value.absent(),
    Value<String?> composer = const Value.absent(),
    Value<String?> memo = const Value.absent(),
  }) => Score(
    nodeId: nodeId ?? this.nodeId,
    fileRel: fileRel ?? this.fileRel,
    pageCount: pageCount ?? this.pageCount,
    bpm: bpm ?? this.bpm,
    timeSigNum: timeSigNum ?? this.timeSigNum,
    timeSigDen: timeSigDen ?? this.timeSigDen,
    clicksPerBar: clicksPerBar ?? this.clicksPerBar,
    countInBars: countInBars ?? this.countInBars,
    leadBeats: leadBeats ?? this.leadBeats,
    pageOrderJson: pageOrderJson.present ? pageOrderJson.value : this.pageOrderJson,
    playOrderJson: playOrderJson.present ? playOrderJson.value : this.playOrderJson,
    composer: composer.present ? composer.value : this.composer,
    memo: memo.present ? memo.value : this.memo,
  );
  Score copyWithCompanion(ScoresCompanion data) {
    return Score(
      nodeId: data.nodeId.present ? data.nodeId.value : this.nodeId,
      fileRel: data.fileRel.present ? data.fileRel.value : this.fileRel,
      pageCount: data.pageCount.present ? data.pageCount.value : this.pageCount,
      bpm: data.bpm.present ? data.bpm.value : this.bpm,
      timeSigNum: data.timeSigNum.present ? data.timeSigNum.value : this.timeSigNum,
      timeSigDen: data.timeSigDen.present ? data.timeSigDen.value : this.timeSigDen,
      clicksPerBar: data.clicksPerBar.present ? data.clicksPerBar.value : this.clicksPerBar,
      countInBars: data.countInBars.present ? data.countInBars.value : this.countInBars,
      leadBeats: data.leadBeats.present ? data.leadBeats.value : this.leadBeats,
      pageOrderJson: data.pageOrderJson.present ? data.pageOrderJson.value : this.pageOrderJson,
      playOrderJson: data.playOrderJson.present ? data.playOrderJson.value : this.playOrderJson,
      composer: data.composer.present ? data.composer.value : this.composer,
      memo: data.memo.present ? data.memo.value : this.memo,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Score(')
          ..write('nodeId: $nodeId, ')
          ..write('fileRel: $fileRel, ')
          ..write('pageCount: $pageCount, ')
          ..write('bpm: $bpm, ')
          ..write('timeSigNum: $timeSigNum, ')
          ..write('timeSigDen: $timeSigDen, ')
          ..write('clicksPerBar: $clicksPerBar, ')
          ..write('countInBars: $countInBars, ')
          ..write('leadBeats: $leadBeats, ')
          ..write('pageOrderJson: $pageOrderJson, ')
          ..write('playOrderJson: $playOrderJson, ')
          ..write('composer: $composer, ')
          ..write('memo: $memo')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    nodeId,
    fileRel,
    pageCount,
    bpm,
    timeSigNum,
    timeSigDen,
    clicksPerBar,
    countInBars,
    leadBeats,
    pageOrderJson,
    playOrderJson,
    composer,
    memo,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Score &&
          other.nodeId == this.nodeId &&
          other.fileRel == this.fileRel &&
          other.pageCount == this.pageCount &&
          other.bpm == this.bpm &&
          other.timeSigNum == this.timeSigNum &&
          other.timeSigDen == this.timeSigDen &&
          other.clicksPerBar == this.clicksPerBar &&
          other.countInBars == this.countInBars &&
          other.leadBeats == this.leadBeats &&
          other.pageOrderJson == this.pageOrderJson &&
          other.playOrderJson == this.playOrderJson &&
          other.composer == this.composer &&
          other.memo == this.memo);
}

class ScoresCompanion extends UpdateCompanion<Score> {
  final Value<int> nodeId;
  final Value<String> fileRel;
  final Value<int> pageCount;
  final Value<double> bpm;
  final Value<int> timeSigNum;
  final Value<int> timeSigDen;
  final Value<int> clicksPerBar;
  final Value<int> countInBars;
  final Value<double> leadBeats;
  final Value<String?> pageOrderJson;
  final Value<String?> playOrderJson;
  final Value<String?> composer;
  final Value<String?> memo;
  const ScoresCompanion({
    this.nodeId = const Value.absent(),
    this.fileRel = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.bpm = const Value.absent(),
    this.timeSigNum = const Value.absent(),
    this.timeSigDen = const Value.absent(),
    this.clicksPerBar = const Value.absent(),
    this.countInBars = const Value.absent(),
    this.leadBeats = const Value.absent(),
    this.pageOrderJson = const Value.absent(),
    this.playOrderJson = const Value.absent(),
    this.composer = const Value.absent(),
    this.memo = const Value.absent(),
  });
  ScoresCompanion.insert({
    this.nodeId = const Value.absent(),
    required String fileRel,
    required int pageCount,
    this.bpm = const Value.absent(),
    this.timeSigNum = const Value.absent(),
    this.timeSigDen = const Value.absent(),
    this.clicksPerBar = const Value.absent(),
    this.countInBars = const Value.absent(),
    this.leadBeats = const Value.absent(),
    this.pageOrderJson = const Value.absent(),
    this.playOrderJson = const Value.absent(),
    this.composer = const Value.absent(),
    this.memo = const Value.absent(),
  }) : fileRel = Value(fileRel),
       pageCount = Value(pageCount);
  static Insertable<Score> custom({
    Expression<int>? nodeId,
    Expression<String>? fileRel,
    Expression<int>? pageCount,
    Expression<double>? bpm,
    Expression<int>? timeSigNum,
    Expression<int>? timeSigDen,
    Expression<int>? clicksPerBar,
    Expression<int>? countInBars,
    Expression<double>? leadBeats,
    Expression<String>? pageOrderJson,
    Expression<String>? playOrderJson,
    Expression<String>? composer,
    Expression<String>? memo,
  }) {
    return RawValuesInsertable({
      if (nodeId != null) 'node_id': nodeId,
      if (fileRel != null) 'file_rel': fileRel,
      if (pageCount != null) 'page_count': pageCount,
      if (bpm != null) 'bpm': bpm,
      if (timeSigNum != null) 'time_sig_num': timeSigNum,
      if (timeSigDen != null) 'time_sig_den': timeSigDen,
      if (clicksPerBar != null) 'clicks_per_bar': clicksPerBar,
      if (countInBars != null) 'count_in_bars': countInBars,
      if (leadBeats != null) 'lead_beats': leadBeats,
      if (pageOrderJson != null) 'page_order_json': pageOrderJson,
      if (playOrderJson != null) 'play_order_json': playOrderJson,
      if (composer != null) 'composer': composer,
      if (memo != null) 'memo': memo,
    });
  }

  ScoresCompanion copyWith({
    Value<int>? nodeId,
    Value<String>? fileRel,
    Value<int>? pageCount,
    Value<double>? bpm,
    Value<int>? timeSigNum,
    Value<int>? timeSigDen,
    Value<int>? clicksPerBar,
    Value<int>? countInBars,
    Value<double>? leadBeats,
    Value<String?>? pageOrderJson,
    Value<String?>? playOrderJson,
    Value<String?>? composer,
    Value<String?>? memo,
  }) {
    return ScoresCompanion(
      nodeId: nodeId ?? this.nodeId,
      fileRel: fileRel ?? this.fileRel,
      pageCount: pageCount ?? this.pageCount,
      bpm: bpm ?? this.bpm,
      timeSigNum: timeSigNum ?? this.timeSigNum,
      timeSigDen: timeSigDen ?? this.timeSigDen,
      clicksPerBar: clicksPerBar ?? this.clicksPerBar,
      countInBars: countInBars ?? this.countInBars,
      leadBeats: leadBeats ?? this.leadBeats,
      pageOrderJson: pageOrderJson ?? this.pageOrderJson,
      playOrderJson: playOrderJson ?? this.playOrderJson,
      composer: composer ?? this.composer,
      memo: memo ?? this.memo,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (nodeId.present) {
      map['node_id'] = Variable<int>(nodeId.value);
    }
    if (fileRel.present) {
      map['file_rel'] = Variable<String>(fileRel.value);
    }
    if (pageCount.present) {
      map['page_count'] = Variable<int>(pageCount.value);
    }
    if (bpm.present) {
      map['bpm'] = Variable<double>(bpm.value);
    }
    if (timeSigNum.present) {
      map['time_sig_num'] = Variable<int>(timeSigNum.value);
    }
    if (timeSigDen.present) {
      map['time_sig_den'] = Variable<int>(timeSigDen.value);
    }
    if (clicksPerBar.present) {
      map['clicks_per_bar'] = Variable<int>(clicksPerBar.value);
    }
    if (countInBars.present) {
      map['count_in_bars'] = Variable<int>(countInBars.value);
    }
    if (leadBeats.present) {
      map['lead_beats'] = Variable<double>(leadBeats.value);
    }
    if (pageOrderJson.present) {
      map['page_order_json'] = Variable<String>(pageOrderJson.value);
    }
    if (playOrderJson.present) {
      map['play_order_json'] = Variable<String>(playOrderJson.value);
    }
    if (composer.present) {
      map['composer'] = Variable<String>(composer.value);
    }
    if (memo.present) {
      map['memo'] = Variable<String>(memo.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScoresCompanion(')
          ..write('nodeId: $nodeId, ')
          ..write('fileRel: $fileRel, ')
          ..write('pageCount: $pageCount, ')
          ..write('bpm: $bpm, ')
          ..write('timeSigNum: $timeSigNum, ')
          ..write('timeSigDen: $timeSigDen, ')
          ..write('clicksPerBar: $clicksPerBar, ')
          ..write('countInBars: $countInBars, ')
          ..write('leadBeats: $leadBeats, ')
          ..write('pageOrderJson: $pageOrderJson, ')
          ..write('playOrderJson: $playOrderJson, ')
          ..write('composer: $composer, ')
          ..write('memo: $memo')
          ..write(')'))
        .toString();
  }
}

class $ScorePagesTable extends ScorePages with TableInfo<$ScorePagesTable, ScorePage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScorePagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _scoreIdMeta = const VerificationMeta('scoreId');
  @override
  late final GeneratedColumn<int> scoreId = GeneratedColumn<int>(
    'score_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES scores (node_id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _pageIndexMeta = const VerificationMeta('pageIndex');
  @override
  late final GeneratedColumn<int> pageIndex = GeneratedColumn<int>(
    'page_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _barCountMeta = const VerificationMeta('barCount');
  @override
  late final GeneratedColumn<int> barCount = GeneratedColumn<int>(
    'bar_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(4),
  );
  static const VerificationMeta _bpmMeta = const VerificationMeta('bpm');
  @override
  late final GeneratedColumn<double> bpm = GeneratedColumn<double>(
    'bpm',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _clicksPerBarMeta = const VerificationMeta('clicksPerBar');
  @override
  late final GeneratedColumn<int> clicksPerBar = GeneratedColumn<int>(
    'clicks_per_bar',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [scoreId, pageIndex, barCount, bpm, clicksPerBar];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'score_pages';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScorePage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('score_id')) {
      context.handle(_scoreIdMeta, scoreId.isAcceptableOrUnknown(data['score_id']!, _scoreIdMeta));
    } else if (isInserting) {
      context.missing(_scoreIdMeta);
    }
    if (data.containsKey('page_index')) {
      context.handle(
        _pageIndexMeta,
        pageIndex.isAcceptableOrUnknown(data['page_index']!, _pageIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_pageIndexMeta);
    }
    if (data.containsKey('bar_count')) {
      context.handle(
        _barCountMeta,
        barCount.isAcceptableOrUnknown(data['bar_count']!, _barCountMeta),
      );
    }
    if (data.containsKey('bpm')) {
      context.handle(_bpmMeta, bpm.isAcceptableOrUnknown(data['bpm']!, _bpmMeta));
    }
    if (data.containsKey('clicks_per_bar')) {
      context.handle(
        _clicksPerBarMeta,
        clicksPerBar.isAcceptableOrUnknown(data['clicks_per_bar']!, _clicksPerBarMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scoreId, pageIndex};
  @override
  ScorePage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScorePage(
      scoreId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}score_id'],
      )!,
      pageIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_index'],
      )!,
      barCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bar_count'],
      )!,
      bpm: attachedDatabase.typeMapping.read(DriftSqlType.double, data['${effectivePrefix}bpm']),
      clicksPerBar: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}clicks_per_bar'],
      ),
    );
  }

  @override
  $ScorePagesTable createAlias(String alias) {
    return $ScorePagesTable(attachedDatabase, alias);
  }
}

class ScorePage extends DataClass implements Insertable<ScorePage> {
  final int scoreId;
  final int pageIndex;

  /// 이 페이지가 화면에 떠 있는 동안 흐르는 마디 수. 페이지 중간 도돌이표는 여기에 합산함.
  final int barCount;
  final double? bpm;
  final int? clicksPerBar;
  const ScorePage({
    required this.scoreId,
    required this.pageIndex,
    required this.barCount,
    this.bpm,
    this.clicksPerBar,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['score_id'] = Variable<int>(scoreId);
    map['page_index'] = Variable<int>(pageIndex);
    map['bar_count'] = Variable<int>(barCount);
    if (!nullToAbsent || bpm != null) {
      map['bpm'] = Variable<double>(bpm);
    }
    if (!nullToAbsent || clicksPerBar != null) {
      map['clicks_per_bar'] = Variable<int>(clicksPerBar);
    }
    return map;
  }

  ScorePagesCompanion toCompanion(bool nullToAbsent) {
    return ScorePagesCompanion(
      scoreId: Value(scoreId),
      pageIndex: Value(pageIndex),
      barCount: Value(barCount),
      bpm: bpm == null && nullToAbsent ? const Value.absent() : Value(bpm),
      clicksPerBar: clicksPerBar == null && nullToAbsent
          ? const Value.absent()
          : Value(clicksPerBar),
    );
  }

  factory ScorePage.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScorePage(
      scoreId: serializer.fromJson<int>(json['scoreId']),
      pageIndex: serializer.fromJson<int>(json['pageIndex']),
      barCount: serializer.fromJson<int>(json['barCount']),
      bpm: serializer.fromJson<double?>(json['bpm']),
      clicksPerBar: serializer.fromJson<int?>(json['clicksPerBar']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scoreId': serializer.toJson<int>(scoreId),
      'pageIndex': serializer.toJson<int>(pageIndex),
      'barCount': serializer.toJson<int>(barCount),
      'bpm': serializer.toJson<double?>(bpm),
      'clicksPerBar': serializer.toJson<int?>(clicksPerBar),
    };
  }

  ScorePage copyWith({
    int? scoreId,
    int? pageIndex,
    int? barCount,
    Value<double?> bpm = const Value.absent(),
    Value<int?> clicksPerBar = const Value.absent(),
  }) => ScorePage(
    scoreId: scoreId ?? this.scoreId,
    pageIndex: pageIndex ?? this.pageIndex,
    barCount: barCount ?? this.barCount,
    bpm: bpm.present ? bpm.value : this.bpm,
    clicksPerBar: clicksPerBar.present ? clicksPerBar.value : this.clicksPerBar,
  );
  ScorePage copyWithCompanion(ScorePagesCompanion data) {
    return ScorePage(
      scoreId: data.scoreId.present ? data.scoreId.value : this.scoreId,
      pageIndex: data.pageIndex.present ? data.pageIndex.value : this.pageIndex,
      barCount: data.barCount.present ? data.barCount.value : this.barCount,
      bpm: data.bpm.present ? data.bpm.value : this.bpm,
      clicksPerBar: data.clicksPerBar.present ? data.clicksPerBar.value : this.clicksPerBar,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScorePage(')
          ..write('scoreId: $scoreId, ')
          ..write('pageIndex: $pageIndex, ')
          ..write('barCount: $barCount, ')
          ..write('bpm: $bpm, ')
          ..write('clicksPerBar: $clicksPerBar')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(scoreId, pageIndex, barCount, bpm, clicksPerBar);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScorePage &&
          other.scoreId == this.scoreId &&
          other.pageIndex == this.pageIndex &&
          other.barCount == this.barCount &&
          other.bpm == this.bpm &&
          other.clicksPerBar == this.clicksPerBar);
}

class ScorePagesCompanion extends UpdateCompanion<ScorePage> {
  final Value<int> scoreId;
  final Value<int> pageIndex;
  final Value<int> barCount;
  final Value<double?> bpm;
  final Value<int?> clicksPerBar;
  final Value<int> rowid;
  const ScorePagesCompanion({
    this.scoreId = const Value.absent(),
    this.pageIndex = const Value.absent(),
    this.barCount = const Value.absent(),
    this.bpm = const Value.absent(),
    this.clicksPerBar = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ScorePagesCompanion.insert({
    required int scoreId,
    required int pageIndex,
    this.barCount = const Value.absent(),
    this.bpm = const Value.absent(),
    this.clicksPerBar = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : scoreId = Value(scoreId),
       pageIndex = Value(pageIndex);
  static Insertable<ScorePage> custom({
    Expression<int>? scoreId,
    Expression<int>? pageIndex,
    Expression<int>? barCount,
    Expression<double>? bpm,
    Expression<int>? clicksPerBar,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scoreId != null) 'score_id': scoreId,
      if (pageIndex != null) 'page_index': pageIndex,
      if (barCount != null) 'bar_count': barCount,
      if (bpm != null) 'bpm': bpm,
      if (clicksPerBar != null) 'clicks_per_bar': clicksPerBar,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ScorePagesCompanion copyWith({
    Value<int>? scoreId,
    Value<int>? pageIndex,
    Value<int>? barCount,
    Value<double?>? bpm,
    Value<int?>? clicksPerBar,
    Value<int>? rowid,
  }) {
    return ScorePagesCompanion(
      scoreId: scoreId ?? this.scoreId,
      pageIndex: pageIndex ?? this.pageIndex,
      barCount: barCount ?? this.barCount,
      bpm: bpm ?? this.bpm,
      clicksPerBar: clicksPerBar ?? this.clicksPerBar,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scoreId.present) {
      map['score_id'] = Variable<int>(scoreId.value);
    }
    if (pageIndex.present) {
      map['page_index'] = Variable<int>(pageIndex.value);
    }
    if (barCount.present) {
      map['bar_count'] = Variable<int>(barCount.value);
    }
    if (bpm.present) {
      map['bpm'] = Variable<double>(bpm.value);
    }
    if (clicksPerBar.present) {
      map['clicks_per_bar'] = Variable<int>(clicksPerBar.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScorePagesCompanion(')
          ..write('scoreId: $scoreId, ')
          ..write('pageIndex: $pageIndex, ')
          ..write('barCount: $barCount, ')
          ..write('bpm: $bpm, ')
          ..write('clicksPerBar: $clicksPerBar, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AnnotationsTable extends Annotations with TableInfo<$AnnotationsTable, Annotation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AnnotationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _scoreIdMeta = const VerificationMeta('scoreId');
  @override
  late final GeneratedColumn<int> scoreId = GeneratedColumn<int>(
    'score_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES scores (node_id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _pageIndexMeta = const VerificationMeta('pageIndex');
  @override
  late final GeneratedColumn<int> pageIndex = GeneratedColumn<int>(
    'page_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _strokesJsonMeta = const VerificationMeta('strokesJson');
  @override
  late final GeneratedColumn<String> strokesJson = GeneratedColumn<String>(
    'strokes_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [scoreId, pageIndex, strokesJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'annotations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Annotation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('score_id')) {
      context.handle(_scoreIdMeta, scoreId.isAcceptableOrUnknown(data['score_id']!, _scoreIdMeta));
    } else if (isInserting) {
      context.missing(_scoreIdMeta);
    }
    if (data.containsKey('page_index')) {
      context.handle(
        _pageIndexMeta,
        pageIndex.isAcceptableOrUnknown(data['page_index']!, _pageIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_pageIndexMeta);
    }
    if (data.containsKey('strokes_json')) {
      context.handle(
        _strokesJsonMeta,
        strokesJson.isAcceptableOrUnknown(data['strokes_json']!, _strokesJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_strokesJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scoreId, pageIndex};
  @override
  Annotation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Annotation(
      scoreId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}score_id'],
      )!,
      pageIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_index'],
      )!,
      strokesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}strokes_json'],
      )!,
    );
  }

  @override
  $AnnotationsTable createAlias(String alias) {
    return $AnnotationsTable(attachedDatabase, alias);
  }
}

class Annotation extends DataClass implements Insertable<Annotation> {
  final int scoreId;
  final int pageIndex;
  final String strokesJson;
  const Annotation({required this.scoreId, required this.pageIndex, required this.strokesJson});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['score_id'] = Variable<int>(scoreId);
    map['page_index'] = Variable<int>(pageIndex);
    map['strokes_json'] = Variable<String>(strokesJson);
    return map;
  }

  AnnotationsCompanion toCompanion(bool nullToAbsent) {
    return AnnotationsCompanion(
      scoreId: Value(scoreId),
      pageIndex: Value(pageIndex),
      strokesJson: Value(strokesJson),
    );
  }

  factory Annotation.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Annotation(
      scoreId: serializer.fromJson<int>(json['scoreId']),
      pageIndex: serializer.fromJson<int>(json['pageIndex']),
      strokesJson: serializer.fromJson<String>(json['strokesJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scoreId': serializer.toJson<int>(scoreId),
      'pageIndex': serializer.toJson<int>(pageIndex),
      'strokesJson': serializer.toJson<String>(strokesJson),
    };
  }

  Annotation copyWith({int? scoreId, int? pageIndex, String? strokesJson}) => Annotation(
    scoreId: scoreId ?? this.scoreId,
    pageIndex: pageIndex ?? this.pageIndex,
    strokesJson: strokesJson ?? this.strokesJson,
  );
  Annotation copyWithCompanion(AnnotationsCompanion data) {
    return Annotation(
      scoreId: data.scoreId.present ? data.scoreId.value : this.scoreId,
      pageIndex: data.pageIndex.present ? data.pageIndex.value : this.pageIndex,
      strokesJson: data.strokesJson.present ? data.strokesJson.value : this.strokesJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Annotation(')
          ..write('scoreId: $scoreId, ')
          ..write('pageIndex: $pageIndex, ')
          ..write('strokesJson: $strokesJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(scoreId, pageIndex, strokesJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Annotation &&
          other.scoreId == this.scoreId &&
          other.pageIndex == this.pageIndex &&
          other.strokesJson == this.strokesJson);
}

class AnnotationsCompanion extends UpdateCompanion<Annotation> {
  final Value<int> scoreId;
  final Value<int> pageIndex;
  final Value<String> strokesJson;
  final Value<int> rowid;
  const AnnotationsCompanion({
    this.scoreId = const Value.absent(),
    this.pageIndex = const Value.absent(),
    this.strokesJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AnnotationsCompanion.insert({
    required int scoreId,
    required int pageIndex,
    required String strokesJson,
    this.rowid = const Value.absent(),
  }) : scoreId = Value(scoreId),
       pageIndex = Value(pageIndex),
       strokesJson = Value(strokesJson);
  static Insertable<Annotation> custom({
    Expression<int>? scoreId,
    Expression<int>? pageIndex,
    Expression<String>? strokesJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scoreId != null) 'score_id': scoreId,
      if (pageIndex != null) 'page_index': pageIndex,
      if (strokesJson != null) 'strokes_json': strokesJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AnnotationsCompanion copyWith({
    Value<int>? scoreId,
    Value<int>? pageIndex,
    Value<String>? strokesJson,
    Value<int>? rowid,
  }) {
    return AnnotationsCompanion(
      scoreId: scoreId ?? this.scoreId,
      pageIndex: pageIndex ?? this.pageIndex,
      strokesJson: strokesJson ?? this.strokesJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scoreId.present) {
      map['score_id'] = Variable<int>(scoreId.value);
    }
    if (pageIndex.present) {
      map['page_index'] = Variable<int>(pageIndex.value);
    }
    if (strokesJson.present) {
      map['strokes_json'] = Variable<String>(strokesJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AnnotationsCompanion(')
          ..write('scoreId: $scoreId, ')
          ..write('pageIndex: $pageIndex, ')
          ..write('strokesJson: $strokesJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(Insertable<Setting> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(_keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(_valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String value;
  const Setting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory Setting.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  Setting copyWith({String? key, String? value}) =>
      Setting(key: key ?? this.key, value: value ?? this.value);
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting && other.key == this.key && other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$BatonDatabase extends GeneratedDatabase {
  _$BatonDatabase(QueryExecutor e) : super(e);
  $BatonDatabaseManager get managers => $BatonDatabaseManager(this);
  late final $NodesTable nodes = $NodesTable(this);
  late final $ScoresTable scores = $ScoresTable(this);
  late final $ScorePagesTable scorePages = $ScorePagesTable(this);
  late final $AnnotationsTable annotations = $AnnotationsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    nodes,
    scores,
    scorePages,
    annotations,
    settings,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName('nodes', limitUpdateKind: UpdateKind.delete),
      result: [TableUpdate('scores', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName('scores', limitUpdateKind: UpdateKind.delete),
      result: [TableUpdate('score_pages', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName('scores', limitUpdateKind: UpdateKind.delete),
      result: [TableUpdate('annotations', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$NodesTableCreateCompanionBuilder = NodesCompanion Function({
  Value<int> id,
  Value<int?> parentId,
  required NodeKind kind,
  required String name,
  Value<int> sortIndex,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
});
typedef $$NodesTableUpdateCompanionBuilder = NodesCompanion Function({
  Value<int> id,
  Value<int?> parentId,
  Value<NodeKind> kind,
  Value<String> name,
  Value<int> sortIndex,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
});

final class $$NodesTableReferences extends BaseReferences<_$BatonDatabase, $NodesTable, Node> {
  $$NodesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $NodesTable _parentIdTable(_$BatonDatabase db) =>
      db.nodes.createAlias('nodes__parent_id__nodes__id');

  $$NodesTableProcessedTableManager? get parentId {
    final $_column = $_itemColumn<int>('parent_id');
    if ($_column == null) return null;
    final manager = $$NodesTableTableManager(
      $_db,
      $_db.nodes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_parentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$ScoresTable, List<Score>> _scoresRefsTable(_$BatonDatabase db) =>
      MultiTypedResultKey.fromTable(db.scores, aliasName: 'nodes__id__scores__node_id');

  $$ScoresTableProcessedTableManager get scoresRefs {
    final manager = $$ScoresTableTableManager(
      $_db,
      $_db.scores,
    ).filter((f) => f.nodeId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_scoresRefsTable($_db));
    return ProcessedTableManager(manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$NodesTableFilterComposer extends Composer<_$BatonDatabase, $NodesTable> {
  $$NodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<NodeKind, NodeKind, String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortIndex =>
      $composableBuilder(column: $table.sortIndex, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  $$NodesTableFilterComposer get parentId {
    final $$NodesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.nodes,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$NodesTableFilterComposer(
            $db: $db,
            $table: $db.nodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> scoresRefs(Expression<bool> Function($$ScoresTableFilterComposer f) f) {
    final $$ScoresTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scores,
      getReferencedColumn: (t) => t.nodeId,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$ScoresTableFilterComposer(
            $db: $db,
            $table: $db.scores,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NodesTableOrderingComposer extends Composer<_$BatonDatabase, $NodesTable> {
  $$NodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortIndex =>
      $composableBuilder(column: $table.sortIndex, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  $$NodesTableOrderingComposer get parentId {
    final $$NodesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.nodes,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$NodesTableOrderingComposer(
            $db: $db,
            $table: $db.nodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NodesTableAnnotationComposer extends Composer<_$BatonDatabase, $NodesTable> {
  $$NodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id => $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<NodeKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortIndex =>
      $composableBuilder(column: $table.sortIndex, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$NodesTableAnnotationComposer get parentId {
    final $$NodesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.nodes,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$NodesTableAnnotationComposer(
            $db: $db,
            $table: $db.nodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> scoresRefs<T extends Object>(
    Expression<T> Function($$ScoresTableAnnotationComposer a) f,
  ) {
    final $$ScoresTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scores,
      getReferencedColumn: (t) => t.nodeId,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$ScoresTableAnnotationComposer(
            $db: $db,
            $table: $db.scores,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NodesTableTableManager
    extends
        RootTableManager<
          _$BatonDatabase,
          $NodesTable,
          Node,
          $$NodesTableFilterComposer,
          $$NodesTableOrderingComposer,
          $$NodesTableAnnotationComposer,
          $$NodesTableCreateCompanionBuilder,
          $$NodesTableUpdateCompanionBuilder,
          (Node, $$NodesTableReferences),
          Node,
          PrefetchHooks Function({bool parentId, bool scoresRefs})
        > {
  $$NodesTableTableManager(_$BatonDatabase db, $NodesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$NodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$NodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$NodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> parentId = const Value.absent(),
                Value<NodeKind> kind = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortIndex = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
              }) => NodesCompanion(
                id: id,
                parentId: parentId,
                kind: kind,
                name: name,
                sortIndex: sortIndex,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> parentId = const Value.absent(),
                required NodeKind kind,
                required String name,
                Value<int> sortIndex = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
              }) => NodesCompanion.insert(
                id: id,
                parentId: parentId,
                kind: kind,
                name: name,
                sortIndex: sortIndex,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
              ),
          withReferenceMapper: (p0) =>
              p0.map((e) => (e.readTable(table), $$NodesTableReferences(db, table, e))).toList(),
          prefetchHooksCallback: ({parentId = false, scoresRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (scoresRefs) db.scores],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (parentId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.parentId,
                        referencedTable: $$NodesTableReferences._parentIdTable(db),
                        referencedColumn: $$NodesTableReferences._parentIdTable(db).id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (scoresRefs)
                    await $_getPrefetchedData<Node, $NodesTable, Score>(
                      currentTable: table,
                      referencedTable: $$NodesTableReferences._scoresRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$NodesTableReferences(db, table, p0).scoresRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.nodeId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$NodesTableProcessedTableManager =
    ProcessedTableManager<
      _$BatonDatabase,
      $NodesTable,
      Node,
      $$NodesTableFilterComposer,
      $$NodesTableOrderingComposer,
      $$NodesTableAnnotationComposer,
      $$NodesTableCreateCompanionBuilder,
      $$NodesTableUpdateCompanionBuilder,
      (Node, $$NodesTableReferences),
      Node,
      PrefetchHooks Function({bool parentId, bool scoresRefs})
    >;
typedef $$ScoresTableCreateCompanionBuilder = ScoresCompanion Function({
  Value<int> nodeId,
  required String fileRel,
  required int pageCount,
  Value<double> bpm,
  Value<int> timeSigNum,
  Value<int> timeSigDen,
  Value<int> clicksPerBar,
  Value<int> countInBars,
  Value<double> leadBeats,
  Value<String?> pageOrderJson,
  Value<String?> playOrderJson,
  Value<String?> composer,
  Value<String?> memo,
});
typedef $$ScoresTableUpdateCompanionBuilder = ScoresCompanion Function({
  Value<int> nodeId,
  Value<String> fileRel,
  Value<int> pageCount,
  Value<double> bpm,
  Value<int> timeSigNum,
  Value<int> timeSigDen,
  Value<int> clicksPerBar,
  Value<int> countInBars,
  Value<double> leadBeats,
  Value<String?> pageOrderJson,
  Value<String?> playOrderJson,
  Value<String?> composer,
  Value<String?> memo,
});

final class $$ScoresTableReferences extends BaseReferences<_$BatonDatabase, $ScoresTable, Score> {
  $$ScoresTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $NodesTable _nodeIdTable(_$BatonDatabase db) =>
      db.nodes.createAlias('scores__node_id__nodes__id');

  $$NodesTableProcessedTableManager get nodeId {
    final $_column = $_itemColumn<int>('node_id')!;

    final manager = $$NodesTableTableManager(
      $_db,
      $_db.nodes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_nodeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$ScoresTableFilterComposer extends Composer<_$BatonDatabase, $ScoresTable> {
  $$ScoresTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get fileRel =>
      $composableBuilder(column: $table.fileRel, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get pageCount =>
      $composableBuilder(column: $table.pageCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get bpm =>
      $composableBuilder(column: $table.bpm, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get timeSigNum =>
      $composableBuilder(column: $table.timeSigNum, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get timeSigDen =>
      $composableBuilder(column: $table.timeSigDen, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get clicksPerBar =>
      $composableBuilder(column: $table.clicksPerBar, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get countInBars =>
      $composableBuilder(column: $table.countInBars, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get leadBeats =>
      $composableBuilder(column: $table.leadBeats, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pageOrderJson =>
      $composableBuilder(column: $table.pageOrderJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get playOrderJson =>
      $composableBuilder(column: $table.playOrderJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get composer =>
      $composableBuilder(column: $table.composer, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get memo =>
      $composableBuilder(column: $table.memo, builder: (column) => ColumnFilters(column));

  $$NodesTableFilterComposer get nodeId {
    final $$NodesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.nodeId,
      referencedTable: $db.nodes,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$NodesTableFilterComposer(
            $db: $db,
            $table: $db.nodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ScoresTableOrderingComposer extends Composer<_$BatonDatabase, $ScoresTable> {
  $$ScoresTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get fileRel =>
      $composableBuilder(column: $table.fileRel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get pageCount =>
      $composableBuilder(column: $table.pageCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get bpm =>
      $composableBuilder(column: $table.bpm, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get timeSigNum =>
      $composableBuilder(column: $table.timeSigNum, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get timeSigDen =>
      $composableBuilder(column: $table.timeSigDen, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get clicksPerBar =>
      $composableBuilder(column: $table.clicksPerBar, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get countInBars =>
      $composableBuilder(column: $table.countInBars, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get leadBeats =>
      $composableBuilder(column: $table.leadBeats, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pageOrderJson => $composableBuilder(
    column: $table.pageOrderJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playOrderJson => $composableBuilder(
    column: $table.playOrderJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get composer =>
      $composableBuilder(column: $table.composer, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get memo =>
      $composableBuilder(column: $table.memo, builder: (column) => ColumnOrderings(column));

  $$NodesTableOrderingComposer get nodeId {
    final $$NodesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.nodeId,
      referencedTable: $db.nodes,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$NodesTableOrderingComposer(
            $db: $db,
            $table: $db.nodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ScoresTableAnnotationComposer extends Composer<_$BatonDatabase, $ScoresTable> {
  $$ScoresTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get fileRel =>
      $composableBuilder(column: $table.fileRel, builder: (column) => column);

  GeneratedColumn<int> get pageCount =>
      $composableBuilder(column: $table.pageCount, builder: (column) => column);

  GeneratedColumn<double> get bpm =>
      $composableBuilder(column: $table.bpm, builder: (column) => column);

  GeneratedColumn<int> get timeSigNum =>
      $composableBuilder(column: $table.timeSigNum, builder: (column) => column);

  GeneratedColumn<int> get timeSigDen =>
      $composableBuilder(column: $table.timeSigDen, builder: (column) => column);

  GeneratedColumn<int> get clicksPerBar =>
      $composableBuilder(column: $table.clicksPerBar, builder: (column) => column);

  GeneratedColumn<int> get countInBars =>
      $composableBuilder(column: $table.countInBars, builder: (column) => column);

  GeneratedColumn<double> get leadBeats =>
      $composableBuilder(column: $table.leadBeats, builder: (column) => column);

  GeneratedColumn<String> get pageOrderJson =>
      $composableBuilder(column: $table.pageOrderJson, builder: (column) => column);

  GeneratedColumn<String> get playOrderJson =>
      $composableBuilder(column: $table.playOrderJson, builder: (column) => column);

  GeneratedColumn<String> get composer =>
      $composableBuilder(column: $table.composer, builder: (column) => column);

  GeneratedColumn<String> get memo =>
      $composableBuilder(column: $table.memo, builder: (column) => column);

  $$NodesTableAnnotationComposer get nodeId {
    final $$NodesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.nodeId,
      referencedTable: $db.nodes,
      getReferencedColumn: (t) => t.id,
      builder: (joinBuilder, {$addJoinBuilderToRootComposer, $removeJoinBuilderFromRootComposer}) =>
          $$NodesTableAnnotationComposer(
            $db: $db,
            $table: $db.nodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer: $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ScoresTableTableManager
    extends
        RootTableManager<
          _$BatonDatabase,
          $ScoresTable,
          Score,
          $$ScoresTableFilterComposer,
          $$ScoresTableOrderingComposer,
          $$ScoresTableAnnotationComposer,
          $$ScoresTableCreateCompanionBuilder,
          $$ScoresTableUpdateCompanionBuilder,
          (Score, $$ScoresTableReferences),
          Score,
          PrefetchHooks Function({bool nodeId})
        > {
  $$ScoresTableTableManager(_$BatonDatabase db, $ScoresTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$ScoresTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$ScoresTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ScoresTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> nodeId = const Value.absent(),
                Value<String> fileRel = const Value.absent(),
                Value<int> pageCount = const Value.absent(),
                Value<double> bpm = const Value.absent(),
                Value<int> timeSigNum = const Value.absent(),
                Value<int> timeSigDen = const Value.absent(),
                Value<int> clicksPerBar = const Value.absent(),
                Value<int> countInBars = const Value.absent(),
                Value<double> leadBeats = const Value.absent(),
                Value<String?> pageOrderJson = const Value.absent(),
                Value<String?> playOrderJson = const Value.absent(),
                Value<String?> composer = const Value.absent(),
                Value<String?> memo = const Value.absent(),
              }) => ScoresCompanion(
                nodeId: nodeId,
                fileRel: fileRel,
                pageCount: pageCount,
                bpm: bpm,
                timeSigNum: timeSigNum,
                timeSigDen: timeSigDen,
                clicksPerBar: clicksPerBar,
                countInBars: countInBars,
                leadBeats: leadBeats,
                pageOrderJson: pageOrderJson,
                playOrderJson: playOrderJson,
                composer: composer,
                memo: memo,
              ),
          createCompanionCallback:
              ({
                Value<int> nodeId = const Value.absent(),
                required String fileRel,
                required int pageCount,
                Value<double> bpm = const Value.absent(),
                Value<int> timeSigNum = const Value.absent(),
                Value<int> timeSigDen = const Value.absent(),
                Value<int> clicksPerBar = const Value.absent(),
                Value<int> countInBars = const Value.absent(),
                Value<double> leadBeats = const Value.absent(),
                Value<String?> pageOrderJson = const Value.absent(),
                Value<String?> playOrderJson = const Value.absent(),
                Value<String?> composer = const Value.absent(),
                Value<String?> memo = const Value.absent(),
              }) => ScoresCompanion.insert(
                nodeId: nodeId,
                fileRel: fileRel,
                pageCount: pageCount,
                bpm: bpm,
                timeSigNum: timeSigNum,
                timeSigDen: timeSigDen,
                clicksPerBar: clicksPerBar,
                countInBars: countInBars,
                leadBeats: leadBeats,
                pageOrderJson: pageOrderJson,
                playOrderJson: playOrderJson,
                composer: composer,
                memo: memo,
              ),
          withReferenceMapper: (p0) =>
              p0.map((e) => (e.readTable(table), $$ScoresTableReferences(db, table, e))).toList(),
          prefetchHooksCallback: ({nodeId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (nodeId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.nodeId,
                        referencedTable: $$ScoresTableReferences._nodeIdTable(db),
                        referencedColumn: $$ScoresTableReferences._nodeIdTable(db).id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ScoresTableProcessedTableManager =
    ProcessedTableManager<
      _$BatonDatabase,
      $ScoresTable,
      Score,
      $$ScoresTableFilterComposer,
      $$ScoresTableOrderingComposer,
      $$ScoresTableAnnotationComposer,
      $$ScoresTableCreateCompanionBuilder,
      $$ScoresTableUpdateCompanionBuilder,
      (Score, $$ScoresTableReferences),
      Score,
      PrefetchHooks Function({bool nodeId})
    >;
typedef $$ScorePagesTableCreateCompanionBuilder = ScorePagesCompanion Function({
  required int scoreId,
  required int pageIndex,
  Value<int> barCount,
  Value<double?> bpm,
  Value<int?> clicksPerBar,
  Value<int> rowid,
});
typedef $$ScorePagesTableUpdateCompanionBuilder = ScorePagesCompanion Function({
  Value<int> scoreId,
  Value<int> pageIndex,
  Value<int> barCount,
  Value<double?> bpm,
  Value<int?> clicksPerBar,
  Value<int> rowid,
});

class $$ScorePagesTableFilterComposer extends Composer<_$BatonDatabase, $ScorePagesTable> {
  $$ScorePagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get pageIndex =>
      $composableBuilder(column: $table.pageIndex, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get barCount =>
      $composableBuilder(column: $table.barCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get bpm =>
      $composableBuilder(column: $table.bpm, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get clicksPerBar =>
      $composableBuilder(column: $table.clicksPerBar, builder: (column) => ColumnFilters(column));
}

class $$ScorePagesTableOrderingComposer extends Composer<_$BatonDatabase, $ScorePagesTable> {
  $$ScorePagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get pageIndex =>
      $composableBuilder(column: $table.pageIndex, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get barCount =>
      $composableBuilder(column: $table.barCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get bpm =>
      $composableBuilder(column: $table.bpm, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get clicksPerBar =>
      $composableBuilder(column: $table.clicksPerBar, builder: (column) => ColumnOrderings(column));
}

class $$ScorePagesTableAnnotationComposer extends Composer<_$BatonDatabase, $ScorePagesTable> {
  $$ScorePagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get pageIndex =>
      $composableBuilder(column: $table.pageIndex, builder: (column) => column);

  GeneratedColumn<int> get barCount =>
      $composableBuilder(column: $table.barCount, builder: (column) => column);

  GeneratedColumn<double> get bpm =>
      $composableBuilder(column: $table.bpm, builder: (column) => column);

  GeneratedColumn<int> get clicksPerBar =>
      $composableBuilder(column: $table.clicksPerBar, builder: (column) => column);
}

class $$ScorePagesTableTableManager
    extends
        RootTableManager<
          _$BatonDatabase,
          $ScorePagesTable,
          ScorePage,
          $$ScorePagesTableFilterComposer,
          $$ScorePagesTableOrderingComposer,
          $$ScorePagesTableAnnotationComposer,
          $$ScorePagesTableCreateCompanionBuilder,
          $$ScorePagesTableUpdateCompanionBuilder,
          (ScorePage, BaseReferences<_$BatonDatabase, $ScorePagesTable, ScorePage>),
          ScorePage,
          PrefetchHooks Function()
        > {
  $$ScorePagesTableTableManager(_$BatonDatabase db, $ScorePagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$ScorePagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$ScorePagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ScorePagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> scoreId = const Value.absent(),
                Value<int> pageIndex = const Value.absent(),
                Value<int> barCount = const Value.absent(),
                Value<double?> bpm = const Value.absent(),
                Value<int?> clicksPerBar = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScorePagesCompanion(
                scoreId: scoreId,
                pageIndex: pageIndex,
                barCount: barCount,
                bpm: bpm,
                clicksPerBar: clicksPerBar,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int scoreId,
                required int pageIndex,
                Value<int> barCount = const Value.absent(),
                Value<double?> bpm = const Value.absent(),
                Value<int?> clicksPerBar = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScorePagesCompanion.insert(
                scoreId: scoreId,
                pageIndex: pageIndex,
                barCount: barCount,
                bpm: bpm,
                clicksPerBar: clicksPerBar,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) =>
              p0.map((e) => (e.readTable(table), BaseReferences(db, table, e))).toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ScorePagesTableProcessedTableManager =
    ProcessedTableManager<
      _$BatonDatabase,
      $ScorePagesTable,
      ScorePage,
      $$ScorePagesTableFilterComposer,
      $$ScorePagesTableOrderingComposer,
      $$ScorePagesTableAnnotationComposer,
      $$ScorePagesTableCreateCompanionBuilder,
      $$ScorePagesTableUpdateCompanionBuilder,
      (ScorePage, BaseReferences<_$BatonDatabase, $ScorePagesTable, ScorePage>),
      ScorePage,
      PrefetchHooks Function()
    >;
typedef $$AnnotationsTableCreateCompanionBuilder = AnnotationsCompanion Function({
  required int scoreId,
  required int pageIndex,
  required String strokesJson,
  Value<int> rowid,
});
typedef $$AnnotationsTableUpdateCompanionBuilder = AnnotationsCompanion Function({
  Value<int> scoreId,
  Value<int> pageIndex,
  Value<String> strokesJson,
  Value<int> rowid,
});

class $$AnnotationsTableFilterComposer extends Composer<_$BatonDatabase, $AnnotationsTable> {
  $$AnnotationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get pageIndex =>
      $composableBuilder(column: $table.pageIndex, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get strokesJson =>
      $composableBuilder(column: $table.strokesJson, builder: (column) => ColumnFilters(column));
}

class $$AnnotationsTableOrderingComposer extends Composer<_$BatonDatabase, $AnnotationsTable> {
  $$AnnotationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get pageIndex =>
      $composableBuilder(column: $table.pageIndex, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get strokesJson =>
      $composableBuilder(column: $table.strokesJson, builder: (column) => ColumnOrderings(column));
}

class $$AnnotationsTableAnnotationComposer extends Composer<_$BatonDatabase, $AnnotationsTable> {
  $$AnnotationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get pageIndex =>
      $composableBuilder(column: $table.pageIndex, builder: (column) => column);

  GeneratedColumn<String> get strokesJson =>
      $composableBuilder(column: $table.strokesJson, builder: (column) => column);
}

class $$AnnotationsTableTableManager
    extends
        RootTableManager<
          _$BatonDatabase,
          $AnnotationsTable,
          Annotation,
          $$AnnotationsTableFilterComposer,
          $$AnnotationsTableOrderingComposer,
          $$AnnotationsTableAnnotationComposer,
          $$AnnotationsTableCreateCompanionBuilder,
          $$AnnotationsTableUpdateCompanionBuilder,
          (Annotation, BaseReferences<_$BatonDatabase, $AnnotationsTable, Annotation>),
          Annotation,
          PrefetchHooks Function()
        > {
  $$AnnotationsTableTableManager(_$BatonDatabase db, $AnnotationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$AnnotationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$AnnotationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AnnotationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> scoreId = const Value.absent(),
                Value<int> pageIndex = const Value.absent(),
                Value<String> strokesJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AnnotationsCompanion(
                scoreId: scoreId,
                pageIndex: pageIndex,
                strokesJson: strokesJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int scoreId,
                required int pageIndex,
                required String strokesJson,
                Value<int> rowid = const Value.absent(),
              }) => AnnotationsCompanion.insert(
                scoreId: scoreId,
                pageIndex: pageIndex,
                strokesJson: strokesJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) =>
              p0.map((e) => (e.readTable(table), BaseReferences(db, table, e))).toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AnnotationsTableProcessedTableManager =
    ProcessedTableManager<
      _$BatonDatabase,
      $AnnotationsTable,
      Annotation,
      $$AnnotationsTableFilterComposer,
      $$AnnotationsTableOrderingComposer,
      $$AnnotationsTableAnnotationComposer,
      $$AnnotationsTableCreateCompanionBuilder,
      $$AnnotationsTableUpdateCompanionBuilder,
      (Annotation, BaseReferences<_$BatonDatabase, $AnnotationsTable, Annotation>),
      Annotation,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer extends Composer<_$BatonDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$SettingsTableOrderingComposer extends Composer<_$BatonDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$SettingsTableAnnotationComposer extends Composer<_$BatonDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$BatonDatabase,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$BatonDatabase, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$BatonDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) =>
              p0.map((e) => (e.readTable(table), BaseReferences(db, table, e))).toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$BatonDatabase,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$BatonDatabase, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;

class $BatonDatabaseManager {
  final _$BatonDatabase _db;
  $BatonDatabaseManager(this._db);
  $$NodesTableTableManager get nodes => $$NodesTableTableManager(_db, _db.nodes);
  $$ScoresTableTableManager get scores => $$ScoresTableTableManager(_db, _db.scores);
  $$ScorePagesTableTableManager get scorePages =>
      $$ScorePagesTableTableManager(_db, _db.scorePages);
  $$AnnotationsTableTableManager get annotations =>
      $$AnnotationsTableTableManager(_db, _db.annotations);
  $$SettingsTableTableManager get settings => $$SettingsTableTableManager(_db, _db.settings);
}
