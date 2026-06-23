// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drift_service.dart';

// ignore_for_file: type=lint
class $AttendanceProofsTable extends AttendanceProofs with TableInfo<$AttendanceProofsTable, AttendanceProof>{
@override final GeneratedDatabase attachedDatabase;
final String? _alias;
$AttendanceProofsTable(this.attachedDatabase, [this._alias]);
static const VerificationMeta _idMeta = const VerificationMeta('id');
@override
late final GeneratedColumn<String> id = GeneratedColumn<String>('id', aliasedName, false, additionalChecks: GeneratedColumn.checkTextLength(minTextLength: 36,maxTextLength: 36), type: DriftSqlType.string, requiredDuringInsert: true);
static const VerificationMeta _sessionIdMeta = const VerificationMeta('sessionId');
@override
late final GeneratedColumn<String> sessionId = GeneratedColumn<String>('session_id', aliasedName, false, additionalChecks: GeneratedColumn.checkTextLength(minTextLength: 36,maxTextLength: 36), type: DriftSqlType.string, requiredDuringInsert: true);
static const VerificationMeta _studentUidMeta = const VerificationMeta('studentUid');
@override
late final GeneratedColumn<String> studentUid = GeneratedColumn<String>('student_uid', aliasedName, false, type: DriftSqlType.string, requiredDuringInsert: true);
static const VerificationMeta _hmacTokenMeta = const VerificationMeta('hmacToken');
@override
late final GeneratedColumn<String> hmacToken = GeneratedColumn<String>('hmac_token', aliasedName, false, type: DriftSqlType.string, requiredDuringInsert: true);
static const VerificationMeta _rssiMeta = const VerificationMeta('rssi');
@override
late final GeneratedColumn<int> rssi = GeneratedColumn<int>('rssi', aliasedName, false, type: DriftSqlType.int, requiredDuringInsert: true);
static const VerificationMeta _timestampMeta = const VerificationMeta('timestamp');
@override
late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>('timestamp', aliasedName, false, type: DriftSqlType.dateTime, requiredDuringInsert: true);
static const VerificationMeta _gpsLatMeta = const VerificationMeta('gpsLat');
@override
late final GeneratedColumn<double> gpsLat = GeneratedColumn<double>('gps_lat', aliasedName, true, type: DriftSqlType.double, requiredDuringInsert: false);
static const VerificationMeta _gpsLngMeta = const VerificationMeta('gpsLng');
@override
late final GeneratedColumn<double> gpsLng = GeneratedColumn<double>('gps_lng', aliasedName, true, type: DriftSqlType.double, requiredDuringInsert: false);
static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
@override
late final GeneratedColumn<bool> synced = GeneratedColumn<bool>('synced', aliasedName, false, type: DriftSqlType.bool, requiredDuringInsert: false, defaultConstraints: GeneratedColumn.constraintIsAlways('CHECK ("synced" IN (0, 1))'), defaultValue: const Constant(false));
@override
List<GeneratedColumn> get $columns => [id, sessionId, studentUid, hmacToken, rssi, timestamp, gpsLat, gpsLng, synced];
@override
String get aliasedName => _alias ?? actualTableName;
@override
 String get actualTableName => $name;
static const String $name = 'attendance_proofs';
@override
VerificationContext validateIntegrity(Insertable<AttendanceProof> instance, {bool isInserting = false}) {
final context = VerificationContext();
final data = instance.toColumns(true);
if (data.containsKey('id')) {
context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));} else if (isInserting) {
context.missing(_idMeta);
}
if (data.containsKey('session_id')) {
context.handle(_sessionIdMeta, sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta));} else if (isInserting) {
context.missing(_sessionIdMeta);
}
if (data.containsKey('student_uid')) {
context.handle(_studentUidMeta, studentUid.isAcceptableOrUnknown(data['student_uid']!, _studentUidMeta));} else if (isInserting) {
context.missing(_studentUidMeta);
}
if (data.containsKey('hmac_token')) {
context.handle(_hmacTokenMeta, hmacToken.isAcceptableOrUnknown(data['hmac_token']!, _hmacTokenMeta));} else if (isInserting) {
context.missing(_hmacTokenMeta);
}
if (data.containsKey('rssi')) {
context.handle(_rssiMeta, rssi.isAcceptableOrUnknown(data['rssi']!, _rssiMeta));} else if (isInserting) {
context.missing(_rssiMeta);
}
if (data.containsKey('timestamp')) {
context.handle(_timestampMeta, timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta));} else if (isInserting) {
context.missing(_timestampMeta);
}
if (data.containsKey('gps_lat')) {
context.handle(_gpsLatMeta, gpsLat.isAcceptableOrUnknown(data['gps_lat']!, _gpsLatMeta));}if (data.containsKey('gps_lng')) {
context.handle(_gpsLngMeta, gpsLng.isAcceptableOrUnknown(data['gps_lng']!, _gpsLngMeta));}if (data.containsKey('synced')) {
context.handle(_syncedMeta, synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta));}return context;
}
@override
Set<GeneratedColumn> get $primaryKey => {id};
@override
List<Set<GeneratedColumn>> get uniqueKeys => [{sessionId, studentUid},
];
@override AttendanceProof map(Map<String, dynamic> data, {String? tablePrefix})  {
final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';return AttendanceProof(id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!, sessionId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}session_id'])!, studentUid: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}student_uid'])!, hmacToken: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}hmac_token'])!, rssi: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}rssi'])!, timestamp: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}timestamp'])!, gpsLat: attachedDatabase.typeMapping.read(DriftSqlType.double, data['${effectivePrefix}gps_lat']), gpsLng: attachedDatabase.typeMapping.read(DriftSqlType.double, data['${effectivePrefix}gps_lng']), synced: attachedDatabase.typeMapping.read(DriftSqlType.bool, data['${effectivePrefix}synced'])!, );
}
@override
$AttendanceProofsTable createAlias(String alias) {
return $AttendanceProofsTable(attachedDatabase, alias);}}class AttendanceProof extends DataClass implements Insertable<AttendanceProof> 
{
/// UUID v4 — packet ID from the mesh packet that carried this proof.
final String id;
/// Session ID broadcast by the teacher node.
final String sessionId;
/// Firebase UID of the student whose presence is being recorded.
final String studentUid;
/// HMAC-SHA256 token proving temporal presence (90 s rolling window).
final String hmacToken;
/// Raw RSSI value at time of capture (negative integer, e.g. -65).
final int rssi;
/// Unix timestamp of BLE packet capture.
final DateTime timestamp;
/// GPS latitude at time of capture — null when location unavailable.
final double? gpsLat;
/// GPS longitude at time of capture — null when location unavailable.
final double? gpsLng;
/// False until this row is successfully written to Firestore.
final bool synced;
const AttendanceProof({required this.id, required this.sessionId, required this.studentUid, required this.hmacToken, required this.rssi, required this.timestamp, this.gpsLat, this.gpsLng, required this.synced});@override
Map<String, Expression> toColumns(bool nullToAbsent) {
final map = <String, Expression> {};map['id'] = Variable<String>(id);
map['session_id'] = Variable<String>(sessionId);
map['student_uid'] = Variable<String>(studentUid);
map['hmac_token'] = Variable<String>(hmacToken);
map['rssi'] = Variable<int>(rssi);
map['timestamp'] = Variable<DateTime>(timestamp);
if (!nullToAbsent || gpsLat != null){map['gps_lat'] = Variable<double>(gpsLat);
}if (!nullToAbsent || gpsLng != null){map['gps_lng'] = Variable<double>(gpsLng);
}map['synced'] = Variable<bool>(synced);
return map; 
}
AttendanceProofsCompanion toCompanion(bool nullToAbsent) {
return AttendanceProofsCompanion(id: Value(id),sessionId: Value(sessionId),studentUid: Value(studentUid),hmacToken: Value(hmacToken),rssi: Value(rssi),timestamp: Value(timestamp),gpsLat: gpsLat == null && nullToAbsent ? const Value.absent() : Value(gpsLat),gpsLng: gpsLng == null && nullToAbsent ? const Value.absent() : Value(gpsLng),synced: Value(synced),);
}
factory AttendanceProof.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
serializer ??= driftRuntimeOptions.defaultSerializer;
return AttendanceProof(id: serializer.fromJson<String>(json['id']),sessionId: serializer.fromJson<String>(json['sessionId']),studentUid: serializer.fromJson<String>(json['studentUid']),hmacToken: serializer.fromJson<String>(json['hmacToken']),rssi: serializer.fromJson<int>(json['rssi']),timestamp: serializer.fromJson<DateTime>(json['timestamp']),gpsLat: serializer.fromJson<double?>(json['gpsLat']),gpsLng: serializer.fromJson<double?>(json['gpsLng']),synced: serializer.fromJson<bool>(json['synced']),);}
@override Map<String, dynamic> toJson({ValueSerializer? serializer}) {
serializer ??= driftRuntimeOptions.defaultSerializer;
return <String, dynamic>{
'id': serializer.toJson<String>(id),'sessionId': serializer.toJson<String>(sessionId),'studentUid': serializer.toJson<String>(studentUid),'hmacToken': serializer.toJson<String>(hmacToken),'rssi': serializer.toJson<int>(rssi),'timestamp': serializer.toJson<DateTime>(timestamp),'gpsLat': serializer.toJson<double?>(gpsLat),'gpsLng': serializer.toJson<double?>(gpsLng),'synced': serializer.toJson<bool>(synced),};}AttendanceProof copyWith({String? id,String? sessionId,String? studentUid,String? hmacToken,int? rssi,DateTime? timestamp,Value<double?> gpsLat = const Value.absent(),Value<double?> gpsLng = const Value.absent(),bool? synced}) => AttendanceProof(id: id ?? this.id,sessionId: sessionId ?? this.sessionId,studentUid: studentUid ?? this.studentUid,hmacToken: hmacToken ?? this.hmacToken,rssi: rssi ?? this.rssi,timestamp: timestamp ?? this.timestamp,gpsLat: gpsLat.present ? gpsLat.value : this.gpsLat,gpsLng: gpsLng.present ? gpsLng.value : this.gpsLng,synced: synced ?? this.synced,);AttendanceProof copyWithCompanion(AttendanceProofsCompanion data) {
return AttendanceProof(
id: data.id.present ? data.id.value : this.id,sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,studentUid: data.studentUid.present ? data.studentUid.value : this.studentUid,hmacToken: data.hmacToken.present ? data.hmacToken.value : this.hmacToken,rssi: data.rssi.present ? data.rssi.value : this.rssi,timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,gpsLat: data.gpsLat.present ? data.gpsLat.value : this.gpsLat,gpsLng: data.gpsLng.present ? data.gpsLng.value : this.gpsLng,synced: data.synced.present ? data.synced.value : this.synced,);
}
@override
String toString() {return (StringBuffer('AttendanceProof(')..write('id: $id, ')..write('sessionId: $sessionId, ')..write('studentUid: $studentUid, ')..write('hmacToken: $hmacToken, ')..write('rssi: $rssi, ')..write('timestamp: $timestamp, ')..write('gpsLat: $gpsLat, ')..write('gpsLng: $gpsLng, ')..write('synced: $synced')..write(')')).toString();}
@override
 int get hashCode => Object.hash(id, sessionId, studentUid, hmacToken, rssi, timestamp, gpsLat, gpsLng, synced);@override
bool operator ==(Object other) => identical(this, other) || (other is AttendanceProof && other.id == this.id && other.sessionId == this.sessionId && other.studentUid == this.studentUid && other.hmacToken == this.hmacToken && other.rssi == this.rssi && other.timestamp == this.timestamp && other.gpsLat == this.gpsLat && other.gpsLng == this.gpsLng && other.synced == this.synced);
}class AttendanceProofsCompanion extends UpdateCompanion<AttendanceProof> {
final Value<String> id;
final Value<String> sessionId;
final Value<String> studentUid;
final Value<String> hmacToken;
final Value<int> rssi;
final Value<DateTime> timestamp;
final Value<double?> gpsLat;
final Value<double?> gpsLng;
final Value<bool> synced;
final Value<int> rowid;
const AttendanceProofsCompanion({this.id = const Value.absent(),this.sessionId = const Value.absent(),this.studentUid = const Value.absent(),this.hmacToken = const Value.absent(),this.rssi = const Value.absent(),this.timestamp = const Value.absent(),this.gpsLat = const Value.absent(),this.gpsLng = const Value.absent(),this.synced = const Value.absent(),this.rowid = const Value.absent(),});
AttendanceProofsCompanion.insert({required String id,required String sessionId,required String studentUid,required String hmacToken,required int rssi,required DateTime timestamp,this.gpsLat = const Value.absent(),this.gpsLng = const Value.absent(),this.synced = const Value.absent(),this.rowid = const Value.absent(),}): id = Value(id), sessionId = Value(sessionId), studentUid = Value(studentUid), hmacToken = Value(hmacToken), rssi = Value(rssi), timestamp = Value(timestamp);
static Insertable<AttendanceProof> custom({Expression<String>? id, 
Expression<String>? sessionId, 
Expression<String>? studentUid, 
Expression<String>? hmacToken, 
Expression<int>? rssi, 
Expression<DateTime>? timestamp, 
Expression<double>? gpsLat, 
Expression<double>? gpsLng, 
Expression<bool>? synced, 
Expression<int>? rowid, 
}) {
return RawValuesInsertable({if (id != null)'id': id,if (sessionId != null)'session_id': sessionId,if (studentUid != null)'student_uid': studentUid,if (hmacToken != null)'hmac_token': hmacToken,if (rssi != null)'rssi': rssi,if (timestamp != null)'timestamp': timestamp,if (gpsLat != null)'gps_lat': gpsLat,if (gpsLng != null)'gps_lng': gpsLng,if (synced != null)'synced': synced,if (rowid != null)'rowid': rowid,});
}AttendanceProofsCompanion copyWith({Value<String>? id, Value<String>? sessionId, Value<String>? studentUid, Value<String>? hmacToken, Value<int>? rssi, Value<DateTime>? timestamp, Value<double?>? gpsLat, Value<double?>? gpsLng, Value<bool>? synced, Value<int>? rowid}) {
return AttendanceProofsCompanion(id: id ?? this.id,sessionId: sessionId ?? this.sessionId,studentUid: studentUid ?? this.studentUid,hmacToken: hmacToken ?? this.hmacToken,rssi: rssi ?? this.rssi,timestamp: timestamp ?? this.timestamp,gpsLat: gpsLat ?? this.gpsLat,gpsLng: gpsLng ?? this.gpsLng,synced: synced ?? this.synced,rowid: rowid ?? this.rowid,);
}
@override
Map<String, Expression> toColumns(bool nullToAbsent) {
final map = <String, Expression> {};if (id.present) {
map['id'] = Variable<String>(id.value);}
if (sessionId.present) {
map['session_id'] = Variable<String>(sessionId.value);}
if (studentUid.present) {
map['student_uid'] = Variable<String>(studentUid.value);}
if (hmacToken.present) {
map['hmac_token'] = Variable<String>(hmacToken.value);}
if (rssi.present) {
map['rssi'] = Variable<int>(rssi.value);}
if (timestamp.present) {
map['timestamp'] = Variable<DateTime>(timestamp.value);}
if (gpsLat.present) {
map['gps_lat'] = Variable<double>(gpsLat.value);}
if (gpsLng.present) {
map['gps_lng'] = Variable<double>(gpsLng.value);}
if (synced.present) {
map['synced'] = Variable<bool>(synced.value);}
if (rowid.present) {
map['rowid'] = Variable<int>(rowid.value);}
return map; 
}
@override
String toString() {return (StringBuffer('AttendanceProofsCompanion(')..write('id: $id, ')..write('sessionId: $sessionId, ')..write('studentUid: $studentUid, ')..write('hmacToken: $hmacToken, ')..write('rssi: $rssi, ')..write('timestamp: $timestamp, ')..write('gpsLat: $gpsLat, ')..write('gpsLng: $gpsLng, ')..write('synced: $synced, ')..write('rowid: $rowid')..write(')')).toString();}
}
class $MessageRecordsTable extends MessageRecords with TableInfo<$MessageRecordsTable, MessageRecord>{
@override final GeneratedDatabase attachedDatabase;
final String? _alias;
$MessageRecordsTable(this.attachedDatabase, [this._alias]);
static const VerificationMeta _idMeta = const VerificationMeta('id');
@override
late final GeneratedColumn<String> id = GeneratedColumn<String>('id', aliasedName, false, additionalChecks: GeneratedColumn.checkTextLength(minTextLength: 36,maxTextLength: 36), type: DriftSqlType.string, requiredDuringInsert: true);
static const VerificationMeta _senderUidMeta = const VerificationMeta('senderUid');
@override
late final GeneratedColumn<String> senderUid = GeneratedColumn<String>('sender_uid', aliasedName, false, type: DriftSqlType.string, requiredDuringInsert: true);
static const VerificationMeta _contentEncryptedMeta = const VerificationMeta('contentEncrypted');
@override
late final GeneratedColumn<String> contentEncrypted = GeneratedColumn<String>('content_encrypted', aliasedName, false, type: DriftSqlType.string, requiredDuringInsert: true);
static const VerificationMeta _ttlMeta = const VerificationMeta('ttl');
@override
late final GeneratedColumn<int> ttl = GeneratedColumn<int>('ttl', aliasedName, false, type: DriftSqlType.int, requiredDuringInsert: true);
static const VerificationMeta _timestampMeta = const VerificationMeta('timestamp');
@override
late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>('timestamp', aliasedName, false, type: DriftSqlType.dateTime, requiredDuringInsert: true);
static const VerificationMeta _laneMeta = const VerificationMeta('lane');
@override
late final GeneratedColumn<String> lane = GeneratedColumn<String>('lane', aliasedName, false, type: DriftSqlType.string, requiredDuringInsert: false, defaultValue: const Constant('social'));
static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
@override
late final GeneratedColumn<bool> synced = GeneratedColumn<bool>('synced', aliasedName, false, type: DriftSqlType.bool, requiredDuringInsert: false, defaultConstraints: GeneratedColumn.constraintIsAlways('CHECK ("synced" IN (0, 1))'), defaultValue: const Constant(false));
static const VerificationMeta _isReadMeta = const VerificationMeta('isRead');
@override
late final GeneratedColumn<bool> isRead = GeneratedColumn<bool>('is_read', aliasedName, false, type: DriftSqlType.bool, requiredDuringInsert: false, defaultConstraints: GeneratedColumn.constraintIsAlways('CHECK ("is_read" IN (0, 1))'), defaultValue: const Constant(false));
static const VerificationMeta _recipientUidMeta = const VerificationMeta('recipientUid');
@override
late final GeneratedColumn<String> recipientUid = GeneratedColumn<String>('recipient_uid', aliasedName, true, type: DriftSqlType.string, requiredDuringInsert: false);
static const VerificationMeta _cipherBlobMeta = const VerificationMeta('cipherBlob');
@override
late final GeneratedColumn<String> cipherBlob = GeneratedColumn<String>('cipher_blob', aliasedName, true, type: DriftSqlType.string, requiredDuringInsert: false);
@override
List<GeneratedColumn> get $columns => [id, senderUid, contentEncrypted, ttl, timestamp, lane, synced, isRead, recipientUid, cipherBlob];
@override
String get aliasedName => _alias ?? actualTableName;
@override
 String get actualTableName => $name;
static const String $name = 'message_records';
@override
VerificationContext validateIntegrity(Insertable<MessageRecord> instance, {bool isInserting = false}) {
final context = VerificationContext();
final data = instance.toColumns(true);
if (data.containsKey('id')) {
context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));} else if (isInserting) {
context.missing(_idMeta);
}
if (data.containsKey('sender_uid')) {
context.handle(_senderUidMeta, senderUid.isAcceptableOrUnknown(data['sender_uid']!, _senderUidMeta));} else if (isInserting) {
context.missing(_senderUidMeta);
}
if (data.containsKey('content_encrypted')) {
context.handle(_contentEncryptedMeta, contentEncrypted.isAcceptableOrUnknown(data['content_encrypted']!, _contentEncryptedMeta));} else if (isInserting) {
context.missing(_contentEncryptedMeta);
}
if (data.containsKey('ttl')) {
context.handle(_ttlMeta, ttl.isAcceptableOrUnknown(data['ttl']!, _ttlMeta));} else if (isInserting) {
context.missing(_ttlMeta);
}
if (data.containsKey('timestamp')) {
context.handle(_timestampMeta, timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta));} else if (isInserting) {
context.missing(_timestampMeta);
}
if (data.containsKey('lane')) {
context.handle(_laneMeta, lane.isAcceptableOrUnknown(data['lane']!, _laneMeta));}if (data.containsKey('synced')) {
context.handle(_syncedMeta, synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta));}if (data.containsKey('is_read')) {
context.handle(_isReadMeta, isRead.isAcceptableOrUnknown(data['is_read']!, _isReadMeta));}if (data.containsKey('recipient_uid')) {
context.handle(_recipientUidMeta, recipientUid.isAcceptableOrUnknown(data['recipient_uid']!, _recipientUidMeta));}if (data.containsKey('cipher_blob')) {
context.handle(_cipherBlobMeta, cipherBlob.isAcceptableOrUnknown(data['cipher_blob']!, _cipherBlobMeta));}return context;
}
@override
Set<GeneratedColumn> get $primaryKey => {id};
@override MessageRecord map(Map<String, dynamic> data, {String? tablePrefix})  {
final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';return MessageRecord(id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!, senderUid: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}sender_uid'])!, contentEncrypted: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}content_encrypted'])!, ttl: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}ttl'])!, timestamp: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}timestamp'])!, lane: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}lane'])!, synced: attachedDatabase.typeMapping.read(DriftSqlType.bool, data['${effectivePrefix}synced'])!, isRead: attachedDatabase.typeMapping.read(DriftSqlType.bool, data['${effectivePrefix}is_read'])!, recipientUid: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}recipient_uid']), cipherBlob: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}cipher_blob']), );
}
@override
$MessageRecordsTable createAlias(String alias) {
return $MessageRecordsTable(attachedDatabase, alias);}}class MessageRecord extends DataClass implements Insertable<MessageRecord> 
{
/// UUID v4 — globally unique across the mesh (used for dedup).
final String id;
/// Firebase UID of the originating node.
final String senderUid;
/// Encrypted message content. In Milestone 2: UTF-8 plaintext.
/// In Milestone 3: base64-encoded XSalsa20-Poly1305 ciphertext.
final String contentEncrypted;
/// Remaining hops. Decremented by each relay node. Drop at 0.
final int ttl;
/// Original send time from the originating node.
final DateTime timestamp;
/// Routing lane identifier: 'social' | 'broadcast'.
final String lane;
/// False until this row is synced to Firestore cloud storage.
final bool synced;
/// Whether the local user has read this message.
final bool isRead;
/// Recipient's Firebase UID — null for broadcast messages (Lane B group
/// chat, unchanged behaviour). Non-null for a 1:1 direct message
/// (Milestone 7). watchAllMessages()/allMessages() filter this to null so
/// DMs never leak into the public broadcast feed.
final String? recipientUid;
/// Base64 of EncryptedMessage.toBytes() (nonce+mac+ciphertext) — set only
/// for direct messages, null for broadcast rows.
///
/// contentEncrypted always holds human-readable PLAINTEXT for every row
/// (broadcast — unencrypted by design — and DM, after this device either
/// composed or successfully decrypted it). That's what the UI renders
/// directly with zero decrypt step. cipherBlob exists purely so
/// FirebaseSyncEngine has the real ciphertext bytes to mirror to Firestore
/// for DM rows without ever uploading plaintext or re-deriving the
/// ciphertext at sync time.
final String? cipherBlob;
const MessageRecord({required this.id, required this.senderUid, required this.contentEncrypted, required this.ttl, required this.timestamp, required this.lane, required this.synced, required this.isRead, this.recipientUid, this.cipherBlob});@override
Map<String, Expression> toColumns(bool nullToAbsent) {
final map = <String, Expression> {};map['id'] = Variable<String>(id);
map['sender_uid'] = Variable<String>(senderUid);
map['content_encrypted'] = Variable<String>(contentEncrypted);
map['ttl'] = Variable<int>(ttl);
map['timestamp'] = Variable<DateTime>(timestamp);
map['lane'] = Variable<String>(lane);
map['synced'] = Variable<bool>(synced);
map['is_read'] = Variable<bool>(isRead);
if (!nullToAbsent || recipientUid != null){map['recipient_uid'] = Variable<String>(recipientUid);
}if (!nullToAbsent || cipherBlob != null){map['cipher_blob'] = Variable<String>(cipherBlob);
}return map; 
}
MessageRecordsCompanion toCompanion(bool nullToAbsent) {
return MessageRecordsCompanion(id: Value(id),senderUid: Value(senderUid),contentEncrypted: Value(contentEncrypted),ttl: Value(ttl),timestamp: Value(timestamp),lane: Value(lane),synced: Value(synced),isRead: Value(isRead),recipientUid: recipientUid == null && nullToAbsent ? const Value.absent() : Value(recipientUid),cipherBlob: cipherBlob == null && nullToAbsent ? const Value.absent() : Value(cipherBlob),);
}
factory MessageRecord.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
serializer ??= driftRuntimeOptions.defaultSerializer;
return MessageRecord(id: serializer.fromJson<String>(json['id']),senderUid: serializer.fromJson<String>(json['senderUid']),contentEncrypted: serializer.fromJson<String>(json['contentEncrypted']),ttl: serializer.fromJson<int>(json['ttl']),timestamp: serializer.fromJson<DateTime>(json['timestamp']),lane: serializer.fromJson<String>(json['lane']),synced: serializer.fromJson<bool>(json['synced']),isRead: serializer.fromJson<bool>(json['isRead']),recipientUid: serializer.fromJson<String?>(json['recipientUid']),cipherBlob: serializer.fromJson<String?>(json['cipherBlob']),);}
@override Map<String, dynamic> toJson({ValueSerializer? serializer}) {
serializer ??= driftRuntimeOptions.defaultSerializer;
return <String, dynamic>{
'id': serializer.toJson<String>(id),'senderUid': serializer.toJson<String>(senderUid),'contentEncrypted': serializer.toJson<String>(contentEncrypted),'ttl': serializer.toJson<int>(ttl),'timestamp': serializer.toJson<DateTime>(timestamp),'lane': serializer.toJson<String>(lane),'synced': serializer.toJson<bool>(synced),'isRead': serializer.toJson<bool>(isRead),'recipientUid': serializer.toJson<String?>(recipientUid),'cipherBlob': serializer.toJson<String?>(cipherBlob),};}MessageRecord copyWith({String? id,String? senderUid,String? contentEncrypted,int? ttl,DateTime? timestamp,String? lane,bool? synced,bool? isRead,Value<String?> recipientUid = const Value.absent(),Value<String?> cipherBlob = const Value.absent()}) => MessageRecord(id: id ?? this.id,senderUid: senderUid ?? this.senderUid,contentEncrypted: contentEncrypted ?? this.contentEncrypted,ttl: ttl ?? this.ttl,timestamp: timestamp ?? this.timestamp,lane: lane ?? this.lane,synced: synced ?? this.synced,isRead: isRead ?? this.isRead,recipientUid: recipientUid.present ? recipientUid.value : this.recipientUid,cipherBlob: cipherBlob.present ? cipherBlob.value : this.cipherBlob,);MessageRecord copyWithCompanion(MessageRecordsCompanion data) {
return MessageRecord(
id: data.id.present ? data.id.value : this.id,senderUid: data.senderUid.present ? data.senderUid.value : this.senderUid,contentEncrypted: data.contentEncrypted.present ? data.contentEncrypted.value : this.contentEncrypted,ttl: data.ttl.present ? data.ttl.value : this.ttl,timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,lane: data.lane.present ? data.lane.value : this.lane,synced: data.synced.present ? data.synced.value : this.synced,isRead: data.isRead.present ? data.isRead.value : this.isRead,recipientUid: data.recipientUid.present ? data.recipientUid.value : this.recipientUid,cipherBlob: data.cipherBlob.present ? data.cipherBlob.value : this.cipherBlob,);
}
@override
String toString() {return (StringBuffer('MessageRecord(')..write('id: $id, ')..write('senderUid: $senderUid, ')..write('contentEncrypted: $contentEncrypted, ')..write('ttl: $ttl, ')..write('timestamp: $timestamp, ')..write('lane: $lane, ')..write('synced: $synced, ')..write('isRead: $isRead, ')..write('recipientUid: $recipientUid, ')..write('cipherBlob: $cipherBlob')..write(')')).toString();}
@override
 int get hashCode => Object.hash(id, senderUid, contentEncrypted, ttl, timestamp, lane, synced, isRead, recipientUid, cipherBlob);@override
bool operator ==(Object other) => identical(this, other) || (other is MessageRecord && other.id == this.id && other.senderUid == this.senderUid && other.contentEncrypted == this.contentEncrypted && other.ttl == this.ttl && other.timestamp == this.timestamp && other.lane == this.lane && other.synced == this.synced && other.isRead == this.isRead && other.recipientUid == this.recipientUid && other.cipherBlob == this.cipherBlob);
}class MessageRecordsCompanion extends UpdateCompanion<MessageRecord> {
final Value<String> id;
final Value<String> senderUid;
final Value<String> contentEncrypted;
final Value<int> ttl;
final Value<DateTime> timestamp;
final Value<String> lane;
final Value<bool> synced;
final Value<bool> isRead;
final Value<String?> recipientUid;
final Value<String?> cipherBlob;
final Value<int> rowid;
const MessageRecordsCompanion({this.id = const Value.absent(),this.senderUid = const Value.absent(),this.contentEncrypted = const Value.absent(),this.ttl = const Value.absent(),this.timestamp = const Value.absent(),this.lane = const Value.absent(),this.synced = const Value.absent(),this.isRead = const Value.absent(),this.recipientUid = const Value.absent(),this.cipherBlob = const Value.absent(),this.rowid = const Value.absent(),});
MessageRecordsCompanion.insert({required String id,required String senderUid,required String contentEncrypted,required int ttl,required DateTime timestamp,this.lane = const Value.absent(),this.synced = const Value.absent(),this.isRead = const Value.absent(),this.recipientUid = const Value.absent(),this.cipherBlob = const Value.absent(),this.rowid = const Value.absent(),}): id = Value(id), senderUid = Value(senderUid), contentEncrypted = Value(contentEncrypted), ttl = Value(ttl), timestamp = Value(timestamp);
static Insertable<MessageRecord> custom({Expression<String>? id, 
Expression<String>? senderUid, 
Expression<String>? contentEncrypted, 
Expression<int>? ttl, 
Expression<DateTime>? timestamp, 
Expression<String>? lane, 
Expression<bool>? synced, 
Expression<bool>? isRead, 
Expression<String>? recipientUid, 
Expression<String>? cipherBlob, 
Expression<int>? rowid, 
}) {
return RawValuesInsertable({if (id != null)'id': id,if (senderUid != null)'sender_uid': senderUid,if (contentEncrypted != null)'content_encrypted': contentEncrypted,if (ttl != null)'ttl': ttl,if (timestamp != null)'timestamp': timestamp,if (lane != null)'lane': lane,if (synced != null)'synced': synced,if (isRead != null)'is_read': isRead,if (recipientUid != null)'recipient_uid': recipientUid,if (cipherBlob != null)'cipher_blob': cipherBlob,if (rowid != null)'rowid': rowid,});
}MessageRecordsCompanion copyWith({Value<String>? id, Value<String>? senderUid, Value<String>? contentEncrypted, Value<int>? ttl, Value<DateTime>? timestamp, Value<String>? lane, Value<bool>? synced, Value<bool>? isRead, Value<String?>? recipientUid, Value<String?>? cipherBlob, Value<int>? rowid}) {
return MessageRecordsCompanion(id: id ?? this.id,senderUid: senderUid ?? this.senderUid,contentEncrypted: contentEncrypted ?? this.contentEncrypted,ttl: ttl ?? this.ttl,timestamp: timestamp ?? this.timestamp,lane: lane ?? this.lane,synced: synced ?? this.synced,isRead: isRead ?? this.isRead,recipientUid: recipientUid ?? this.recipientUid,cipherBlob: cipherBlob ?? this.cipherBlob,rowid: rowid ?? this.rowid,);
}
@override
Map<String, Expression> toColumns(bool nullToAbsent) {
final map = <String, Expression> {};if (id.present) {
map['id'] = Variable<String>(id.value);}
if (senderUid.present) {
map['sender_uid'] = Variable<String>(senderUid.value);}
if (contentEncrypted.present) {
map['content_encrypted'] = Variable<String>(contentEncrypted.value);}
if (ttl.present) {
map['ttl'] = Variable<int>(ttl.value);}
if (timestamp.present) {
map['timestamp'] = Variable<DateTime>(timestamp.value);}
if (lane.present) {
map['lane'] = Variable<String>(lane.value);}
if (synced.present) {
map['synced'] = Variable<bool>(synced.value);}
if (isRead.present) {
map['is_read'] = Variable<bool>(isRead.value);}
if (recipientUid.present) {
map['recipient_uid'] = Variable<String>(recipientUid.value);}
if (cipherBlob.present) {
map['cipher_blob'] = Variable<String>(cipherBlob.value);}
if (rowid.present) {
map['rowid'] = Variable<int>(rowid.value);}
return map; 
}
@override
String toString() {return (StringBuffer('MessageRecordsCompanion(')..write('id: $id, ')..write('senderUid: $senderUid, ')..write('contentEncrypted: $contentEncrypted, ')..write('ttl: $ttl, ')..write('timestamp: $timestamp, ')..write('lane: $lane, ')..write('synced: $synced, ')..write('isRead: $isRead, ')..write('recipientUid: $recipientUid, ')..write('cipherBlob: $cipherBlob, ')..write('rowid: $rowid')..write(')')).toString();}
}
class $SosRecordsTable extends SosRecords with TableInfo<$SosRecordsTable, SosRecord>{
@override final GeneratedDatabase attachedDatabase;
final String? _alias;
$SosRecordsTable(this.attachedDatabase, [this._alias]);
static const VerificationMeta _idMeta = const VerificationMeta('id');
@override
late final GeneratedColumn<String> id = GeneratedColumn<String>('id', aliasedName, false, additionalChecks: GeneratedColumn.checkTextLength(minTextLength: 36,maxTextLength: 36), type: DriftSqlType.string, requiredDuringInsert: true);
static const VerificationMeta _senderUidMeta = const VerificationMeta('senderUid');
@override
late final GeneratedColumn<String> senderUid = GeneratedColumn<String>('sender_uid', aliasedName, false, type: DriftSqlType.string, requiredDuringInsert: true);
static const VerificationMeta _latitudeMeta = const VerificationMeta('latitude');
@override
late final GeneratedColumn<double> latitude = GeneratedColumn<double>('latitude', aliasedName, false, type: DriftSqlType.double, requiredDuringInsert: true);
static const VerificationMeta _longitudeMeta = const VerificationMeta('longitude');
@override
late final GeneratedColumn<double> longitude = GeneratedColumn<double>('longitude', aliasedName, false, type: DriftSqlType.double, requiredDuringInsert: true);
static const VerificationMeta _ttlMeta = const VerificationMeta('ttl');
@override
late final GeneratedColumn<int> ttl = GeneratedColumn<int>('ttl', aliasedName, false, type: DriftSqlType.int, requiredDuringInsert: true);
static const VerificationMeta _timestampMeta = const VerificationMeta('timestamp');
@override
late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>('timestamp', aliasedName, false, type: DriftSqlType.dateTime, requiredDuringInsert: true);
static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
@override
late final GeneratedColumn<bool> synced = GeneratedColumn<bool>('synced', aliasedName, false, type: DriftSqlType.bool, requiredDuringInsert: false, defaultConstraints: GeneratedColumn.constraintIsAlways('CHECK ("synced" IN (0, 1))'), defaultValue: const Constant(false));
@override
List<GeneratedColumn> get $columns => [id, senderUid, latitude, longitude, ttl, timestamp, synced];
@override
String get aliasedName => _alias ?? actualTableName;
@override
 String get actualTableName => $name;
static const String $name = 'sos_records';
@override
VerificationContext validateIntegrity(Insertable<SosRecord> instance, {bool isInserting = false}) {
final context = VerificationContext();
final data = instance.toColumns(true);
if (data.containsKey('id')) {
context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));} else if (isInserting) {
context.missing(_idMeta);
}
if (data.containsKey('sender_uid')) {
context.handle(_senderUidMeta, senderUid.isAcceptableOrUnknown(data['sender_uid']!, _senderUidMeta));} else if (isInserting) {
context.missing(_senderUidMeta);
}
if (data.containsKey('latitude')) {
context.handle(_latitudeMeta, latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta));} else if (isInserting) {
context.missing(_latitudeMeta);
}
if (data.containsKey('longitude')) {
context.handle(_longitudeMeta, longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta));} else if (isInserting) {
context.missing(_longitudeMeta);
}
if (data.containsKey('ttl')) {
context.handle(_ttlMeta, ttl.isAcceptableOrUnknown(data['ttl']!, _ttlMeta));} else if (isInserting) {
context.missing(_ttlMeta);
}
if (data.containsKey('timestamp')) {
context.handle(_timestampMeta, timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta));} else if (isInserting) {
context.missing(_timestampMeta);
}
if (data.containsKey('synced')) {
context.handle(_syncedMeta, synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta));}return context;
}
@override
Set<GeneratedColumn> get $primaryKey => {id};
@override SosRecord map(Map<String, dynamic> data, {String? tablePrefix})  {
final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';return SosRecord(id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!, senderUid: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}sender_uid'])!, latitude: attachedDatabase.typeMapping.read(DriftSqlType.double, data['${effectivePrefix}latitude'])!, longitude: attachedDatabase.typeMapping.read(DriftSqlType.double, data['${effectivePrefix}longitude'])!, ttl: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}ttl'])!, timestamp: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}timestamp'])!, synced: attachedDatabase.typeMapping.read(DriftSqlType.bool, data['${effectivePrefix}synced'])!, );
}
@override
$SosRecordsTable createAlias(String alias) {
return $SosRecordsTable(attachedDatabase, alias);}}class SosRecord extends DataClass implements Insertable<SosRecord> 
{
/// UUID v4 — globally unique SOS event ID.
final String id;
/// Firebase UID of the person who triggered SOS.
final String senderUid;
/// GPS latitude at time of SOS trigger.
final double latitude;
/// GPS longitude at time of SOS trigger.
final double longitude;
/// Remaining hops (starts at 255, decremented per relay).
final int ttl;
/// Unix timestamp when SOS was first triggered.
final DateTime timestamp;
/// False until this event is acknowledged by Firestore.
final bool synced;
const SosRecord({required this.id, required this.senderUid, required this.latitude, required this.longitude, required this.ttl, required this.timestamp, required this.synced});@override
Map<String, Expression> toColumns(bool nullToAbsent) {
final map = <String, Expression> {};map['id'] = Variable<String>(id);
map['sender_uid'] = Variable<String>(senderUid);
map['latitude'] = Variable<double>(latitude);
map['longitude'] = Variable<double>(longitude);
map['ttl'] = Variable<int>(ttl);
map['timestamp'] = Variable<DateTime>(timestamp);
map['synced'] = Variable<bool>(synced);
return map; 
}
SosRecordsCompanion toCompanion(bool nullToAbsent) {
return SosRecordsCompanion(id: Value(id),senderUid: Value(senderUid),latitude: Value(latitude),longitude: Value(longitude),ttl: Value(ttl),timestamp: Value(timestamp),synced: Value(synced),);
}
factory SosRecord.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
serializer ??= driftRuntimeOptions.defaultSerializer;
return SosRecord(id: serializer.fromJson<String>(json['id']),senderUid: serializer.fromJson<String>(json['senderUid']),latitude: serializer.fromJson<double>(json['latitude']),longitude: serializer.fromJson<double>(json['longitude']),ttl: serializer.fromJson<int>(json['ttl']),timestamp: serializer.fromJson<DateTime>(json['timestamp']),synced: serializer.fromJson<bool>(json['synced']),);}
@override Map<String, dynamic> toJson({ValueSerializer? serializer}) {
serializer ??= driftRuntimeOptions.defaultSerializer;
return <String, dynamic>{
'id': serializer.toJson<String>(id),'senderUid': serializer.toJson<String>(senderUid),'latitude': serializer.toJson<double>(latitude),'longitude': serializer.toJson<double>(longitude),'ttl': serializer.toJson<int>(ttl),'timestamp': serializer.toJson<DateTime>(timestamp),'synced': serializer.toJson<bool>(synced),};}SosRecord copyWith({String? id,String? senderUid,double? latitude,double? longitude,int? ttl,DateTime? timestamp,bool? synced}) => SosRecord(id: id ?? this.id,senderUid: senderUid ?? this.senderUid,latitude: latitude ?? this.latitude,longitude: longitude ?? this.longitude,ttl: ttl ?? this.ttl,timestamp: timestamp ?? this.timestamp,synced: synced ?? this.synced,);SosRecord copyWithCompanion(SosRecordsCompanion data) {
return SosRecord(
id: data.id.present ? data.id.value : this.id,senderUid: data.senderUid.present ? data.senderUid.value : this.senderUid,latitude: data.latitude.present ? data.latitude.value : this.latitude,longitude: data.longitude.present ? data.longitude.value : this.longitude,ttl: data.ttl.present ? data.ttl.value : this.ttl,timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,synced: data.synced.present ? data.synced.value : this.synced,);
}
@override
String toString() {return (StringBuffer('SosRecord(')..write('id: $id, ')..write('senderUid: $senderUid, ')..write('latitude: $latitude, ')..write('longitude: $longitude, ')..write('ttl: $ttl, ')..write('timestamp: $timestamp, ')..write('synced: $synced')..write(')')).toString();}
@override
 int get hashCode => Object.hash(id, senderUid, latitude, longitude, ttl, timestamp, synced);@override
bool operator ==(Object other) => identical(this, other) || (other is SosRecord && other.id == this.id && other.senderUid == this.senderUid && other.latitude == this.latitude && other.longitude == this.longitude && other.ttl == this.ttl && other.timestamp == this.timestamp && other.synced == this.synced);
}class SosRecordsCompanion extends UpdateCompanion<SosRecord> {
final Value<String> id;
final Value<String> senderUid;
final Value<double> latitude;
final Value<double> longitude;
final Value<int> ttl;
final Value<DateTime> timestamp;
final Value<bool> synced;
final Value<int> rowid;
const SosRecordsCompanion({this.id = const Value.absent(),this.senderUid = const Value.absent(),this.latitude = const Value.absent(),this.longitude = const Value.absent(),this.ttl = const Value.absent(),this.timestamp = const Value.absent(),this.synced = const Value.absent(),this.rowid = const Value.absent(),});
SosRecordsCompanion.insert({required String id,required String senderUid,required double latitude,required double longitude,required int ttl,required DateTime timestamp,this.synced = const Value.absent(),this.rowid = const Value.absent(),}): id = Value(id), senderUid = Value(senderUid), latitude = Value(latitude), longitude = Value(longitude), ttl = Value(ttl), timestamp = Value(timestamp);
static Insertable<SosRecord> custom({Expression<String>? id, 
Expression<String>? senderUid, 
Expression<double>? latitude, 
Expression<double>? longitude, 
Expression<int>? ttl, 
Expression<DateTime>? timestamp, 
Expression<bool>? synced, 
Expression<int>? rowid, 
}) {
return RawValuesInsertable({if (id != null)'id': id,if (senderUid != null)'sender_uid': senderUid,if (latitude != null)'latitude': latitude,if (longitude != null)'longitude': longitude,if (ttl != null)'ttl': ttl,if (timestamp != null)'timestamp': timestamp,if (synced != null)'synced': synced,if (rowid != null)'rowid': rowid,});
}SosRecordsCompanion copyWith({Value<String>? id, Value<String>? senderUid, Value<double>? latitude, Value<double>? longitude, Value<int>? ttl, Value<DateTime>? timestamp, Value<bool>? synced, Value<int>? rowid}) {
return SosRecordsCompanion(id: id ?? this.id,senderUid: senderUid ?? this.senderUid,latitude: latitude ?? this.latitude,longitude: longitude ?? this.longitude,ttl: ttl ?? this.ttl,timestamp: timestamp ?? this.timestamp,synced: synced ?? this.synced,rowid: rowid ?? this.rowid,);
}
@override
Map<String, Expression> toColumns(bool nullToAbsent) {
final map = <String, Expression> {};if (id.present) {
map['id'] = Variable<String>(id.value);}
if (senderUid.present) {
map['sender_uid'] = Variable<String>(senderUid.value);}
if (latitude.present) {
map['latitude'] = Variable<double>(latitude.value);}
if (longitude.present) {
map['longitude'] = Variable<double>(longitude.value);}
if (ttl.present) {
map['ttl'] = Variable<int>(ttl.value);}
if (timestamp.present) {
map['timestamp'] = Variable<DateTime>(timestamp.value);}
if (synced.present) {
map['synced'] = Variable<bool>(synced.value);}
if (rowid.present) {
map['rowid'] = Variable<int>(rowid.value);}
return map; 
}
@override
String toString() {return (StringBuffer('SosRecordsCompanion(')..write('id: $id, ')..write('senderUid: $senderUid, ')..write('latitude: $latitude, ')..write('longitude: $longitude, ')..write('ttl: $ttl, ')..write('timestamp: $timestamp, ')..write('synced: $synced, ')..write('rowid: $rowid')..write(')')).toString();}
}
class $SeenPacketsTable extends SeenPackets with TableInfo<$SeenPacketsTable, SeenPacket>{
@override final GeneratedDatabase attachedDatabase;
final String? _alias;
$SeenPacketsTable(this.attachedDatabase, [this._alias]);
static const VerificationMeta _packetIdMeta = const VerificationMeta('packetId');
@override
late final GeneratedColumn<String> packetId = GeneratedColumn<String>('packet_id', aliasedName, false, additionalChecks: GeneratedColumn.checkTextLength(minTextLength: 36,maxTextLength: 36), type: DriftSqlType.string, requiredDuringInsert: true);
static const VerificationMeta _firstSeenMeta = const VerificationMeta('firstSeen');
@override
late final GeneratedColumn<DateTime> firstSeen = GeneratedColumn<DateTime>('first_seen', aliasedName, false, type: DriftSqlType.dateTime, requiredDuringInsert: true);
@override
List<GeneratedColumn> get $columns => [packetId, firstSeen];
@override
String get aliasedName => _alias ?? actualTableName;
@override
 String get actualTableName => $name;
static const String $name = 'seen_packets';
@override
VerificationContext validateIntegrity(Insertable<SeenPacket> instance, {bool isInserting = false}) {
final context = VerificationContext();
final data = instance.toColumns(true);
if (data.containsKey('packet_id')) {
context.handle(_packetIdMeta, packetId.isAcceptableOrUnknown(data['packet_id']!, _packetIdMeta));} else if (isInserting) {
context.missing(_packetIdMeta);
}
if (data.containsKey('first_seen')) {
context.handle(_firstSeenMeta, firstSeen.isAcceptableOrUnknown(data['first_seen']!, _firstSeenMeta));} else if (isInserting) {
context.missing(_firstSeenMeta);
}
return context;
}
@override
Set<GeneratedColumn> get $primaryKey => {packetId};
@override SeenPacket map(Map<String, dynamic> data, {String? tablePrefix})  {
final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';return SeenPacket(packetId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}packet_id'])!, firstSeen: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}first_seen'])!, );
}
@override
$SeenPacketsTable createAlias(String alias) {
return $SeenPacketsTable(attachedDatabase, alias);}}class SeenPacket extends DataClass implements Insertable<SeenPacket> 
{
/// UUID of the mesh packet already processed.
final String packetId;
/// When this node first processed the packet — used for TTL purge.
final DateTime firstSeen;
const SeenPacket({required this.packetId, required this.firstSeen});@override
Map<String, Expression> toColumns(bool nullToAbsent) {
final map = <String, Expression> {};map['packet_id'] = Variable<String>(packetId);
map['first_seen'] = Variable<DateTime>(firstSeen);
return map; 
}
SeenPacketsCompanion toCompanion(bool nullToAbsent) {
return SeenPacketsCompanion(packetId: Value(packetId),firstSeen: Value(firstSeen),);
}
factory SeenPacket.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
serializer ??= driftRuntimeOptions.defaultSerializer;
return SeenPacket(packetId: serializer.fromJson<String>(json['packetId']),firstSeen: serializer.fromJson<DateTime>(json['firstSeen']),);}
@override Map<String, dynamic> toJson({ValueSerializer? serializer}) {
serializer ??= driftRuntimeOptions.defaultSerializer;
return <String, dynamic>{
'packetId': serializer.toJson<String>(packetId),'firstSeen': serializer.toJson<DateTime>(firstSeen),};}SeenPacket copyWith({String? packetId,DateTime? firstSeen}) => SeenPacket(packetId: packetId ?? this.packetId,firstSeen: firstSeen ?? this.firstSeen,);SeenPacket copyWithCompanion(SeenPacketsCompanion data) {
return SeenPacket(
packetId: data.packetId.present ? data.packetId.value : this.packetId,firstSeen: data.firstSeen.present ? data.firstSeen.value : this.firstSeen,);
}
@override
String toString() {return (StringBuffer('SeenPacket(')..write('packetId: $packetId, ')..write('firstSeen: $firstSeen')..write(')')).toString();}
@override
 int get hashCode => Object.hash(packetId, firstSeen);@override
bool operator ==(Object other) => identical(this, other) || (other is SeenPacket && other.packetId == this.packetId && other.firstSeen == this.firstSeen);
}class SeenPacketsCompanion extends UpdateCompanion<SeenPacket> {
final Value<String> packetId;
final Value<DateTime> firstSeen;
final Value<int> rowid;
const SeenPacketsCompanion({this.packetId = const Value.absent(),this.firstSeen = const Value.absent(),this.rowid = const Value.absent(),});
SeenPacketsCompanion.insert({required String packetId,required DateTime firstSeen,this.rowid = const Value.absent(),}): packetId = Value(packetId), firstSeen = Value(firstSeen);
static Insertable<SeenPacket> custom({Expression<String>? packetId, 
Expression<DateTime>? firstSeen, 
Expression<int>? rowid, 
}) {
return RawValuesInsertable({if (packetId != null)'packet_id': packetId,if (firstSeen != null)'first_seen': firstSeen,if (rowid != null)'rowid': rowid,});
}SeenPacketsCompanion copyWith({Value<String>? packetId, Value<DateTime>? firstSeen, Value<int>? rowid}) {
return SeenPacketsCompanion(packetId: packetId ?? this.packetId,firstSeen: firstSeen ?? this.firstSeen,rowid: rowid ?? this.rowid,);
}
@override
Map<String, Expression> toColumns(bool nullToAbsent) {
final map = <String, Expression> {};if (packetId.present) {
map['packet_id'] = Variable<String>(packetId.value);}
if (firstSeen.present) {
map['first_seen'] = Variable<DateTime>(firstSeen.value);}
if (rowid.present) {
map['rowid'] = Variable<int>(rowid.value);}
return map; 
}
@override
String toString() {return (StringBuffer('SeenPacketsCompanion(')..write('packetId: $packetId, ')..write('firstSeen: $firstSeen, ')..write('rowid: $rowid')..write(')')).toString();}
}
class $PeersTable extends Peers with TableInfo<$PeersTable, Peer>{
@override final GeneratedDatabase attachedDatabase;
final String? _alias;
$PeersTable(this.attachedDatabase, [this._alias]);
static const VerificationMeta _peerUidMeta = const VerificationMeta('peerUid');
@override
late final GeneratedColumn<String> peerUid = GeneratedColumn<String>('peer_uid', aliasedName, false, type: DriftSqlType.string, requiredDuringInsert: true);
static const VerificationMeta _lastSeenMeta = const VerificationMeta('lastSeen');
@override
late final GeneratedColumn<DateTime> lastSeen = GeneratedColumn<DateTime>('last_seen', aliasedName, false, type: DriftSqlType.dateTime, requiredDuringInsert: true);
static const VerificationMeta _rssiMeta = const VerificationMeta('rssi');
@override
late final GeneratedColumn<int> rssi = GeneratedColumn<int>('rssi', aliasedName, false, type: DriftSqlType.int, requiredDuringInsert: true);
static const VerificationMeta _publicKeyFingerprintMeta = const VerificationMeta('publicKeyFingerprint');
@override
late final GeneratedColumn<String> publicKeyFingerprint = GeneratedColumn<String>('public_key_fingerprint', aliasedName, false, type: DriftSqlType.string, requiredDuringInsert: false, defaultValue: const Constant(''));
@override
List<GeneratedColumn> get $columns => [peerUid, lastSeen, rssi, publicKeyFingerprint];
@override
String get aliasedName => _alias ?? actualTableName;
@override
 String get actualTableName => $name;
static const String $name = 'peers';
@override
VerificationContext validateIntegrity(Insertable<Peer> instance, {bool isInserting = false}) {
final context = VerificationContext();
final data = instance.toColumns(true);
if (data.containsKey('peer_uid')) {
context.handle(_peerUidMeta, peerUid.isAcceptableOrUnknown(data['peer_uid']!, _peerUidMeta));} else if (isInserting) {
context.missing(_peerUidMeta);
}
if (data.containsKey('last_seen')) {
context.handle(_lastSeenMeta, lastSeen.isAcceptableOrUnknown(data['last_seen']!, _lastSeenMeta));} else if (isInserting) {
context.missing(_lastSeenMeta);
}
if (data.containsKey('rssi')) {
context.handle(_rssiMeta, rssi.isAcceptableOrUnknown(data['rssi']!, _rssiMeta));} else if (isInserting) {
context.missing(_rssiMeta);
}
if (data.containsKey('public_key_fingerprint')) {
context.handle(_publicKeyFingerprintMeta, publicKeyFingerprint.isAcceptableOrUnknown(data['public_key_fingerprint']!, _publicKeyFingerprintMeta));}return context;
}
@override
Set<GeneratedColumn> get $primaryKey => {peerUid};
@override Peer map(Map<String, dynamic> data, {String? tablePrefix})  {
final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';return Peer(peerUid: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}peer_uid'])!, lastSeen: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}last_seen'])!, rssi: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}rssi'])!, publicKeyFingerprint: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}public_key_fingerprint'])!, );
}
@override
$PeersTable createAlias(String alias) {
return $PeersTable(attachedDatabase, alias);}}class Peer extends DataClass implements Insertable<Peer> 
{
/// Firebase UID of the remote peer node.
final String peerUid;
/// When this peer was last seen advertising.
final DateTime lastSeen;
/// Last measured RSSI from this peer (signal strength indicator).
final int rssi;
/// SHA256 fingerprint of peer's Curve25519 public key — set in Milestone 3.
final String publicKeyFingerprint;
const Peer({required this.peerUid, required this.lastSeen, required this.rssi, required this.publicKeyFingerprint});@override
Map<String, Expression> toColumns(bool nullToAbsent) {
final map = <String, Expression> {};map['peer_uid'] = Variable<String>(peerUid);
map['last_seen'] = Variable<DateTime>(lastSeen);
map['rssi'] = Variable<int>(rssi);
map['public_key_fingerprint'] = Variable<String>(publicKeyFingerprint);
return map; 
}
PeersCompanion toCompanion(bool nullToAbsent) {
return PeersCompanion(peerUid: Value(peerUid),lastSeen: Value(lastSeen),rssi: Value(rssi),publicKeyFingerprint: Value(publicKeyFingerprint),);
}
factory Peer.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
serializer ??= driftRuntimeOptions.defaultSerializer;
return Peer(peerUid: serializer.fromJson<String>(json['peerUid']),lastSeen: serializer.fromJson<DateTime>(json['lastSeen']),rssi: serializer.fromJson<int>(json['rssi']),publicKeyFingerprint: serializer.fromJson<String>(json['publicKeyFingerprint']),);}
@override Map<String, dynamic> toJson({ValueSerializer? serializer}) {
serializer ??= driftRuntimeOptions.defaultSerializer;
return <String, dynamic>{
'peerUid': serializer.toJson<String>(peerUid),'lastSeen': serializer.toJson<DateTime>(lastSeen),'rssi': serializer.toJson<int>(rssi),'publicKeyFingerprint': serializer.toJson<String>(publicKeyFingerprint),};}Peer copyWith({String? peerUid,DateTime? lastSeen,int? rssi,String? publicKeyFingerprint}) => Peer(peerUid: peerUid ?? this.peerUid,lastSeen: lastSeen ?? this.lastSeen,rssi: rssi ?? this.rssi,publicKeyFingerprint: publicKeyFingerprint ?? this.publicKeyFingerprint,);Peer copyWithCompanion(PeersCompanion data) {
return Peer(
peerUid: data.peerUid.present ? data.peerUid.value : this.peerUid,lastSeen: data.lastSeen.present ? data.lastSeen.value : this.lastSeen,rssi: data.rssi.present ? data.rssi.value : this.rssi,publicKeyFingerprint: data.publicKeyFingerprint.present ? data.publicKeyFingerprint.value : this.publicKeyFingerprint,);
}
@override
String toString() {return (StringBuffer('Peer(')..write('peerUid: $peerUid, ')..write('lastSeen: $lastSeen, ')..write('rssi: $rssi, ')..write('publicKeyFingerprint: $publicKeyFingerprint')..write(')')).toString();}
@override
 int get hashCode => Object.hash(peerUid, lastSeen, rssi, publicKeyFingerprint);@override
bool operator ==(Object other) => identical(this, other) || (other is Peer && other.peerUid == this.peerUid && other.lastSeen == this.lastSeen && other.rssi == this.rssi && other.publicKeyFingerprint == this.publicKeyFingerprint);
}class PeersCompanion extends UpdateCompanion<Peer> {
final Value<String> peerUid;
final Value<DateTime> lastSeen;
final Value<int> rssi;
final Value<String> publicKeyFingerprint;
final Value<int> rowid;
const PeersCompanion({this.peerUid = const Value.absent(),this.lastSeen = const Value.absent(),this.rssi = const Value.absent(),this.publicKeyFingerprint = const Value.absent(),this.rowid = const Value.absent(),});
PeersCompanion.insert({required String peerUid,required DateTime lastSeen,required int rssi,this.publicKeyFingerprint = const Value.absent(),this.rowid = const Value.absent(),}): peerUid = Value(peerUid), lastSeen = Value(lastSeen), rssi = Value(rssi);
static Insertable<Peer> custom({Expression<String>? peerUid, 
Expression<DateTime>? lastSeen, 
Expression<int>? rssi, 
Expression<String>? publicKeyFingerprint, 
Expression<int>? rowid, 
}) {
return RawValuesInsertable({if (peerUid != null)'peer_uid': peerUid,if (lastSeen != null)'last_seen': lastSeen,if (rssi != null)'rssi': rssi,if (publicKeyFingerprint != null)'public_key_fingerprint': publicKeyFingerprint,if (rowid != null)'rowid': rowid,});
}PeersCompanion copyWith({Value<String>? peerUid, Value<DateTime>? lastSeen, Value<int>? rssi, Value<String>? publicKeyFingerprint, Value<int>? rowid}) {
return PeersCompanion(peerUid: peerUid ?? this.peerUid,lastSeen: lastSeen ?? this.lastSeen,rssi: rssi ?? this.rssi,publicKeyFingerprint: publicKeyFingerprint ?? this.publicKeyFingerprint,rowid: rowid ?? this.rowid,);
}
@override
Map<String, Expression> toColumns(bool nullToAbsent) {
final map = <String, Expression> {};if (peerUid.present) {
map['peer_uid'] = Variable<String>(peerUid.value);}
if (lastSeen.present) {
map['last_seen'] = Variable<DateTime>(lastSeen.value);}
if (rssi.present) {
map['rssi'] = Variable<int>(rssi.value);}
if (publicKeyFingerprint.present) {
map['public_key_fingerprint'] = Variable<String>(publicKeyFingerprint.value);}
if (rowid.present) {
map['rowid'] = Variable<int>(rowid.value);}
return map; 
}
@override
String toString() {return (StringBuffer('PeersCompanion(')..write('peerUid: $peerUid, ')..write('lastSeen: $lastSeen, ')..write('rssi: $rssi, ')..write('publicKeyFingerprint: $publicKeyFingerprint, ')..write('rowid: $rowid')..write(')')).toString();}
}
abstract class _$AppDatabase extends GeneratedDatabase{
_$AppDatabase(QueryExecutor e): super(e);
$AppDatabaseManager get managers => $AppDatabaseManager(this);
late final $AttendanceProofsTable attendanceProofs = $AttendanceProofsTable(this);
late final $MessageRecordsTable messageRecords = $MessageRecordsTable(this);
late final $SosRecordsTable sosRecords = $SosRecordsTable(this);
late final $SeenPacketsTable seenPackets = $SeenPacketsTable(this);
late final $PeersTable peers = $PeersTable(this);
@override
Iterable<TableInfo<Table, Object?>> get allTables => allSchemaEntities.whereType<TableInfo<Table, Object?>>();
@override
List<DatabaseSchemaEntity> get allSchemaEntities => [attendanceProofs, messageRecords, sosRecords, seenPackets, peers];
}
typedef $$AttendanceProofsTableCreateCompanionBuilder = AttendanceProofsCompanion Function({required String id,required String sessionId,required String studentUid,required String hmacToken,required int rssi,required DateTime timestamp,Value<double?> gpsLat,Value<double?> gpsLng,Value<bool> synced,Value<int> rowid,});
typedef $$AttendanceProofsTableUpdateCompanionBuilder = AttendanceProofsCompanion Function({Value<String> id,Value<String> sessionId,Value<String> studentUid,Value<String> hmacToken,Value<int> rssi,Value<DateTime> timestamp,Value<double?> gpsLat,Value<double?> gpsLng,Value<bool> synced,Value<int> rowid,});
class $$AttendanceProofsTableFilterComposer extends Composer<
        _$AppDatabase,
        $AttendanceProofsTable> {
        $$AttendanceProofsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
          ColumnFilters<String> get id => $composableBuilder(
      column: $table.id,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<String> get sessionId => $composableBuilder(
      column: $table.sessionId,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<String> get studentUid => $composableBuilder(
      column: $table.studentUid,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<String> get hmacToken => $composableBuilder(
      column: $table.hmacToken,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<int> get rssi => $composableBuilder(
      column: $table.rssi,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<double> get gpsLat => $composableBuilder(
      column: $table.gpsLat,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<double> get gpsLng => $composableBuilder(
      column: $table.gpsLng,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<bool> get synced => $composableBuilder(
      column: $table.synced,
      builder: (column) => 
      ColumnFilters(column));
      
        }
      class $$AttendanceProofsTableOrderingComposer extends Composer<
        _$AppDatabase,
        $AttendanceProofsTable> {
        $$AttendanceProofsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
          ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<String> get sessionId => $composableBuilder(
      column: $table.sessionId,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<String> get studentUid => $composableBuilder(
      column: $table.studentUid,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<String> get hmacToken => $composableBuilder(
      column: $table.hmacToken,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<int> get rssi => $composableBuilder(
      column: $table.rssi,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<double> get gpsLat => $composableBuilder(
      column: $table.gpsLat,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<double> get gpsLng => $composableBuilder(
      column: $table.gpsLng,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<bool> get synced => $composableBuilder(
      column: $table.synced,
      builder: (column) => 
      ColumnOrderings(column));
      
        }
      class $$AttendanceProofsTableAnnotationComposer extends Composer<
        _$AppDatabase,
        $AttendanceProofsTable> {
        $$AttendanceProofsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
          GeneratedColumn<String> get id => $composableBuilder(
      column: $table.id,
      builder: (column) => column);
      
GeneratedColumn<String> get sessionId => $composableBuilder(
      column: $table.sessionId,
      builder: (column) => column);
      
GeneratedColumn<String> get studentUid => $composableBuilder(
      column: $table.studentUid,
      builder: (column) => column);
      
GeneratedColumn<String> get hmacToken => $composableBuilder(
      column: $table.hmacToken,
      builder: (column) => column);
      
GeneratedColumn<int> get rssi => $composableBuilder(
      column: $table.rssi,
      builder: (column) => column);
      
GeneratedColumn<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp,
      builder: (column) => column);
      
GeneratedColumn<double> get gpsLat => $composableBuilder(
      column: $table.gpsLat,
      builder: (column) => column);
      
GeneratedColumn<double> get gpsLng => $composableBuilder(
      column: $table.gpsLng,
      builder: (column) => column);
      
GeneratedColumn<bool> get synced => $composableBuilder(
      column: $table.synced,
      builder: (column) => column);
      
        }
      class $$AttendanceProofsTableTableManager extends RootTableManager    <_$AppDatabase,
    $AttendanceProofsTable,
    AttendanceProof,
    $$AttendanceProofsTableFilterComposer,
    $$AttendanceProofsTableOrderingComposer,
    $$AttendanceProofsTableAnnotationComposer,
    $$AttendanceProofsTableCreateCompanionBuilder,
    $$AttendanceProofsTableUpdateCompanionBuilder,
    (AttendanceProof,BaseReferences<_$AppDatabase,$AttendanceProofsTable,AttendanceProof>),
    AttendanceProof,
    PrefetchHooks Function()
    > {
    $$AttendanceProofsTableTableManager(_$AppDatabase db, $AttendanceProofsTable table) : super(
      TableManagerState(
        db: db,
        table: table,
        createFilteringComposer: () => $$AttendanceProofsTableFilterComposer($db: db,$table:table),
        createOrderingComposer: () => $$AttendanceProofsTableOrderingComposer($db: db,$table:table),
        createComputedFieldComposer: () => $$AttendanceProofsTableAnnotationComposer($db: db,$table:table),
        updateCompanionCallback: ({Value<String> id = const Value.absent(),Value<String> sessionId = const Value.absent(),Value<String> studentUid = const Value.absent(),Value<String> hmacToken = const Value.absent(),Value<int> rssi = const Value.absent(),Value<DateTime> timestamp = const Value.absent(),Value<double?> gpsLat = const Value.absent(),Value<double?> gpsLng = const Value.absent(),Value<bool> synced = const Value.absent(),Value<int> rowid = const Value.absent(),})=> AttendanceProofsCompanion(id: id,sessionId: sessionId,studentUid: studentUid,hmacToken: hmacToken,rssi: rssi,timestamp: timestamp,gpsLat: gpsLat,gpsLng: gpsLng,synced: synced,rowid: rowid,),
        createCompanionCallback: ({required String id,required String sessionId,required String studentUid,required String hmacToken,required int rssi,required DateTime timestamp,Value<double?> gpsLat = const Value.absent(),Value<double?> gpsLng = const Value.absent(),Value<bool> synced = const Value.absent(),Value<int> rowid = const Value.absent(),})=> AttendanceProofsCompanion.insert(id: id,sessionId: sessionId,studentUid: studentUid,hmacToken: hmacToken,rssi: rssi,timestamp: timestamp,gpsLat: gpsLat,gpsLng: gpsLng,synced: synced,rowid: rowid,),
        withReferenceMapper: (p0) => p0
              .map(
                  (e) =>
                     (e.readTable(table), BaseReferences(db, table, e))
                  )
              .toList(),
        prefetchHooksCallback: null,
        ));
        }
    typedef $$AttendanceProofsTableProcessedTableManager = ProcessedTableManager    <_$AppDatabase,
    $AttendanceProofsTable,
    AttendanceProof,
    $$AttendanceProofsTableFilterComposer,
    $$AttendanceProofsTableOrderingComposer,
    $$AttendanceProofsTableAnnotationComposer,
    $$AttendanceProofsTableCreateCompanionBuilder,
    $$AttendanceProofsTableUpdateCompanionBuilder,
    (AttendanceProof,BaseReferences<_$AppDatabase,$AttendanceProofsTable,AttendanceProof>),
    AttendanceProof,
    PrefetchHooks Function()
    >;typedef $$MessageRecordsTableCreateCompanionBuilder = MessageRecordsCompanion Function({required String id,required String senderUid,required String contentEncrypted,required int ttl,required DateTime timestamp,Value<String> lane,Value<bool> synced,Value<bool> isRead,Value<String?> recipientUid,Value<String?> cipherBlob,Value<int> rowid,});
typedef $$MessageRecordsTableUpdateCompanionBuilder = MessageRecordsCompanion Function({Value<String> id,Value<String> senderUid,Value<String> contentEncrypted,Value<int> ttl,Value<DateTime> timestamp,Value<String> lane,Value<bool> synced,Value<bool> isRead,Value<String?> recipientUid,Value<String?> cipherBlob,Value<int> rowid,});
class $$MessageRecordsTableFilterComposer extends Composer<
        _$AppDatabase,
        $MessageRecordsTable> {
        $$MessageRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
          ColumnFilters<String> get id => $composableBuilder(
      column: $table.id,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<String> get senderUid => $composableBuilder(
      column: $table.senderUid,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<String> get contentEncrypted => $composableBuilder(
      column: $table.contentEncrypted,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<int> get ttl => $composableBuilder(
      column: $table.ttl,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<String> get lane => $composableBuilder(
      column: $table.lane,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<bool> get synced => $composableBuilder(
      column: $table.synced,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<bool> get isRead => $composableBuilder(
      column: $table.isRead,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<String> get recipientUid => $composableBuilder(
      column: $table.recipientUid,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<String> get cipherBlob => $composableBuilder(
      column: $table.cipherBlob,
      builder: (column) => 
      ColumnFilters(column));
      
        }
      class $$MessageRecordsTableOrderingComposer extends Composer<
        _$AppDatabase,
        $MessageRecordsTable> {
        $$MessageRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
          ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<String> get senderUid => $composableBuilder(
      column: $table.senderUid,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<String> get contentEncrypted => $composableBuilder(
      column: $table.contentEncrypted,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<int> get ttl => $composableBuilder(
      column: $table.ttl,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<String> get lane => $composableBuilder(
      column: $table.lane,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<bool> get synced => $composableBuilder(
      column: $table.synced,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<bool> get isRead => $composableBuilder(
      column: $table.isRead,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<String> get recipientUid => $composableBuilder(
      column: $table.recipientUid,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<String> get cipherBlob => $composableBuilder(
      column: $table.cipherBlob,
      builder: (column) => 
      ColumnOrderings(column));
      
        }
      class $$MessageRecordsTableAnnotationComposer extends Composer<
        _$AppDatabase,
        $MessageRecordsTable> {
        $$MessageRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
          GeneratedColumn<String> get id => $composableBuilder(
      column: $table.id,
      builder: (column) => column);
      
GeneratedColumn<String> get senderUid => $composableBuilder(
      column: $table.senderUid,
      builder: (column) => column);
      
GeneratedColumn<String> get contentEncrypted => $composableBuilder(
      column: $table.contentEncrypted,
      builder: (column) => column);
      
GeneratedColumn<int> get ttl => $composableBuilder(
      column: $table.ttl,
      builder: (column) => column);
      
GeneratedColumn<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp,
      builder: (column) => column);
      
GeneratedColumn<String> get lane => $composableBuilder(
      column: $table.lane,
      builder: (column) => column);
      
GeneratedColumn<bool> get synced => $composableBuilder(
      column: $table.synced,
      builder: (column) => column);
      
GeneratedColumn<bool> get isRead => $composableBuilder(
      column: $table.isRead,
      builder: (column) => column);
      
GeneratedColumn<String> get recipientUid => $composableBuilder(
      column: $table.recipientUid,
      builder: (column) => column);
      
GeneratedColumn<String> get cipherBlob => $composableBuilder(
      column: $table.cipherBlob,
      builder: (column) => column);
      
        }
      class $$MessageRecordsTableTableManager extends RootTableManager    <_$AppDatabase,
    $MessageRecordsTable,
    MessageRecord,
    $$MessageRecordsTableFilterComposer,
    $$MessageRecordsTableOrderingComposer,
    $$MessageRecordsTableAnnotationComposer,
    $$MessageRecordsTableCreateCompanionBuilder,
    $$MessageRecordsTableUpdateCompanionBuilder,
    (MessageRecord,BaseReferences<_$AppDatabase,$MessageRecordsTable,MessageRecord>),
    MessageRecord,
    PrefetchHooks Function()
    > {
    $$MessageRecordsTableTableManager(_$AppDatabase db, $MessageRecordsTable table) : super(
      TableManagerState(
        db: db,
        table: table,
        createFilteringComposer: () => $$MessageRecordsTableFilterComposer($db: db,$table:table),
        createOrderingComposer: () => $$MessageRecordsTableOrderingComposer($db: db,$table:table),
        createComputedFieldComposer: () => $$MessageRecordsTableAnnotationComposer($db: db,$table:table),
        updateCompanionCallback: ({Value<String> id = const Value.absent(),Value<String> senderUid = const Value.absent(),Value<String> contentEncrypted = const Value.absent(),Value<int> ttl = const Value.absent(),Value<DateTime> timestamp = const Value.absent(),Value<String> lane = const Value.absent(),Value<bool> synced = const Value.absent(),Value<bool> isRead = const Value.absent(),Value<String?> recipientUid = const Value.absent(),Value<String?> cipherBlob = const Value.absent(),Value<int> rowid = const Value.absent(),})=> MessageRecordsCompanion(id: id,senderUid: senderUid,contentEncrypted: contentEncrypted,ttl: ttl,timestamp: timestamp,lane: lane,synced: synced,isRead: isRead,recipientUid: recipientUid,cipherBlob: cipherBlob,rowid: rowid,),
        createCompanionCallback: ({required String id,required String senderUid,required String contentEncrypted,required int ttl,required DateTime timestamp,Value<String> lane = const Value.absent(),Value<bool> synced = const Value.absent(),Value<bool> isRead = const Value.absent(),Value<String?> recipientUid = const Value.absent(),Value<String?> cipherBlob = const Value.absent(),Value<int> rowid = const Value.absent(),})=> MessageRecordsCompanion.insert(id: id,senderUid: senderUid,contentEncrypted: contentEncrypted,ttl: ttl,timestamp: timestamp,lane: lane,synced: synced,isRead: isRead,recipientUid: recipientUid,cipherBlob: cipherBlob,rowid: rowid,),
        withReferenceMapper: (p0) => p0
              .map(
                  (e) =>
                     (e.readTable(table), BaseReferences(db, table, e))
                  )
              .toList(),
        prefetchHooksCallback: null,
        ));
        }
    typedef $$MessageRecordsTableProcessedTableManager = ProcessedTableManager    <_$AppDatabase,
    $MessageRecordsTable,
    MessageRecord,
    $$MessageRecordsTableFilterComposer,
    $$MessageRecordsTableOrderingComposer,
    $$MessageRecordsTableAnnotationComposer,
    $$MessageRecordsTableCreateCompanionBuilder,
    $$MessageRecordsTableUpdateCompanionBuilder,
    (MessageRecord,BaseReferences<_$AppDatabase,$MessageRecordsTable,MessageRecord>),
    MessageRecord,
    PrefetchHooks Function()
    >;typedef $$SosRecordsTableCreateCompanionBuilder = SosRecordsCompanion Function({required String id,required String senderUid,required double latitude,required double longitude,required int ttl,required DateTime timestamp,Value<bool> synced,Value<int> rowid,});
typedef $$SosRecordsTableUpdateCompanionBuilder = SosRecordsCompanion Function({Value<String> id,Value<String> senderUid,Value<double> latitude,Value<double> longitude,Value<int> ttl,Value<DateTime> timestamp,Value<bool> synced,Value<int> rowid,});
class $$SosRecordsTableFilterComposer extends Composer<
        _$AppDatabase,
        $SosRecordsTable> {
        $$SosRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
          ColumnFilters<String> get id => $composableBuilder(
      column: $table.id,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<String> get senderUid => $composableBuilder(
      column: $table.senderUid,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<double> get latitude => $composableBuilder(
      column: $table.latitude,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<double> get longitude => $composableBuilder(
      column: $table.longitude,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<int> get ttl => $composableBuilder(
      column: $table.ttl,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<bool> get synced => $composableBuilder(
      column: $table.synced,
      builder: (column) => 
      ColumnFilters(column));
      
        }
      class $$SosRecordsTableOrderingComposer extends Composer<
        _$AppDatabase,
        $SosRecordsTable> {
        $$SosRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
          ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<String> get senderUid => $composableBuilder(
      column: $table.senderUid,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<double> get latitude => $composableBuilder(
      column: $table.latitude,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<double> get longitude => $composableBuilder(
      column: $table.longitude,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<int> get ttl => $composableBuilder(
      column: $table.ttl,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<bool> get synced => $composableBuilder(
      column: $table.synced,
      builder: (column) => 
      ColumnOrderings(column));
      
        }
      class $$SosRecordsTableAnnotationComposer extends Composer<
        _$AppDatabase,
        $SosRecordsTable> {
        $$SosRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
          GeneratedColumn<String> get id => $composableBuilder(
      column: $table.id,
      builder: (column) => column);
      
GeneratedColumn<String> get senderUid => $composableBuilder(
      column: $table.senderUid,
      builder: (column) => column);
      
GeneratedColumn<double> get latitude => $composableBuilder(
      column: $table.latitude,
      builder: (column) => column);
      
GeneratedColumn<double> get longitude => $composableBuilder(
      column: $table.longitude,
      builder: (column) => column);
      
GeneratedColumn<int> get ttl => $composableBuilder(
      column: $table.ttl,
      builder: (column) => column);
      
GeneratedColumn<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp,
      builder: (column) => column);
      
GeneratedColumn<bool> get synced => $composableBuilder(
      column: $table.synced,
      builder: (column) => column);
      
        }
      class $$SosRecordsTableTableManager extends RootTableManager    <_$AppDatabase,
    $SosRecordsTable,
    SosRecord,
    $$SosRecordsTableFilterComposer,
    $$SosRecordsTableOrderingComposer,
    $$SosRecordsTableAnnotationComposer,
    $$SosRecordsTableCreateCompanionBuilder,
    $$SosRecordsTableUpdateCompanionBuilder,
    (SosRecord,BaseReferences<_$AppDatabase,$SosRecordsTable,SosRecord>),
    SosRecord,
    PrefetchHooks Function()
    > {
    $$SosRecordsTableTableManager(_$AppDatabase db, $SosRecordsTable table) : super(
      TableManagerState(
        db: db,
        table: table,
        createFilteringComposer: () => $$SosRecordsTableFilterComposer($db: db,$table:table),
        createOrderingComposer: () => $$SosRecordsTableOrderingComposer($db: db,$table:table),
        createComputedFieldComposer: () => $$SosRecordsTableAnnotationComposer($db: db,$table:table),
        updateCompanionCallback: ({Value<String> id = const Value.absent(),Value<String> senderUid = const Value.absent(),Value<double> latitude = const Value.absent(),Value<double> longitude = const Value.absent(),Value<int> ttl = const Value.absent(),Value<DateTime> timestamp = const Value.absent(),Value<bool> synced = const Value.absent(),Value<int> rowid = const Value.absent(),})=> SosRecordsCompanion(id: id,senderUid: senderUid,latitude: latitude,longitude: longitude,ttl: ttl,timestamp: timestamp,synced: synced,rowid: rowid,),
        createCompanionCallback: ({required String id,required String senderUid,required double latitude,required double longitude,required int ttl,required DateTime timestamp,Value<bool> synced = const Value.absent(),Value<int> rowid = const Value.absent(),})=> SosRecordsCompanion.insert(id: id,senderUid: senderUid,latitude: latitude,longitude: longitude,ttl: ttl,timestamp: timestamp,synced: synced,rowid: rowid,),
        withReferenceMapper: (p0) => p0
              .map(
                  (e) =>
                     (e.readTable(table), BaseReferences(db, table, e))
                  )
              .toList(),
        prefetchHooksCallback: null,
        ));
        }
    typedef $$SosRecordsTableProcessedTableManager = ProcessedTableManager    <_$AppDatabase,
    $SosRecordsTable,
    SosRecord,
    $$SosRecordsTableFilterComposer,
    $$SosRecordsTableOrderingComposer,
    $$SosRecordsTableAnnotationComposer,
    $$SosRecordsTableCreateCompanionBuilder,
    $$SosRecordsTableUpdateCompanionBuilder,
    (SosRecord,BaseReferences<_$AppDatabase,$SosRecordsTable,SosRecord>),
    SosRecord,
    PrefetchHooks Function()
    >;typedef $$SeenPacketsTableCreateCompanionBuilder = SeenPacketsCompanion Function({required String packetId,required DateTime firstSeen,Value<int> rowid,});
typedef $$SeenPacketsTableUpdateCompanionBuilder = SeenPacketsCompanion Function({Value<String> packetId,Value<DateTime> firstSeen,Value<int> rowid,});
class $$SeenPacketsTableFilterComposer extends Composer<
        _$AppDatabase,
        $SeenPacketsTable> {
        $$SeenPacketsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
          ColumnFilters<String> get packetId => $composableBuilder(
      column: $table.packetId,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<DateTime> get firstSeen => $composableBuilder(
      column: $table.firstSeen,
      builder: (column) => 
      ColumnFilters(column));
      
        }
      class $$SeenPacketsTableOrderingComposer extends Composer<
        _$AppDatabase,
        $SeenPacketsTable> {
        $$SeenPacketsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
          ColumnOrderings<String> get packetId => $composableBuilder(
      column: $table.packetId,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<DateTime> get firstSeen => $composableBuilder(
      column: $table.firstSeen,
      builder: (column) => 
      ColumnOrderings(column));
      
        }
      class $$SeenPacketsTableAnnotationComposer extends Composer<
        _$AppDatabase,
        $SeenPacketsTable> {
        $$SeenPacketsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
          GeneratedColumn<String> get packetId => $composableBuilder(
      column: $table.packetId,
      builder: (column) => column);
      
GeneratedColumn<DateTime> get firstSeen => $composableBuilder(
      column: $table.firstSeen,
      builder: (column) => column);
      
        }
      class $$SeenPacketsTableTableManager extends RootTableManager    <_$AppDatabase,
    $SeenPacketsTable,
    SeenPacket,
    $$SeenPacketsTableFilterComposer,
    $$SeenPacketsTableOrderingComposer,
    $$SeenPacketsTableAnnotationComposer,
    $$SeenPacketsTableCreateCompanionBuilder,
    $$SeenPacketsTableUpdateCompanionBuilder,
    (SeenPacket,BaseReferences<_$AppDatabase,$SeenPacketsTable,SeenPacket>),
    SeenPacket,
    PrefetchHooks Function()
    > {
    $$SeenPacketsTableTableManager(_$AppDatabase db, $SeenPacketsTable table) : super(
      TableManagerState(
        db: db,
        table: table,
        createFilteringComposer: () => $$SeenPacketsTableFilterComposer($db: db,$table:table),
        createOrderingComposer: () => $$SeenPacketsTableOrderingComposer($db: db,$table:table),
        createComputedFieldComposer: () => $$SeenPacketsTableAnnotationComposer($db: db,$table:table),
        updateCompanionCallback: ({Value<String> packetId = const Value.absent(),Value<DateTime> firstSeen = const Value.absent(),Value<int> rowid = const Value.absent(),})=> SeenPacketsCompanion(packetId: packetId,firstSeen: firstSeen,rowid: rowid,),
        createCompanionCallback: ({required String packetId,required DateTime firstSeen,Value<int> rowid = const Value.absent(),})=> SeenPacketsCompanion.insert(packetId: packetId,firstSeen: firstSeen,rowid: rowid,),
        withReferenceMapper: (p0) => p0
              .map(
                  (e) =>
                     (e.readTable(table), BaseReferences(db, table, e))
                  )
              .toList(),
        prefetchHooksCallback: null,
        ));
        }
    typedef $$SeenPacketsTableProcessedTableManager = ProcessedTableManager    <_$AppDatabase,
    $SeenPacketsTable,
    SeenPacket,
    $$SeenPacketsTableFilterComposer,
    $$SeenPacketsTableOrderingComposer,
    $$SeenPacketsTableAnnotationComposer,
    $$SeenPacketsTableCreateCompanionBuilder,
    $$SeenPacketsTableUpdateCompanionBuilder,
    (SeenPacket,BaseReferences<_$AppDatabase,$SeenPacketsTable,SeenPacket>),
    SeenPacket,
    PrefetchHooks Function()
    >;typedef $$PeersTableCreateCompanionBuilder = PeersCompanion Function({required String peerUid,required DateTime lastSeen,required int rssi,Value<String> publicKeyFingerprint,Value<int> rowid,});
typedef $$PeersTableUpdateCompanionBuilder = PeersCompanion Function({Value<String> peerUid,Value<DateTime> lastSeen,Value<int> rssi,Value<String> publicKeyFingerprint,Value<int> rowid,});
class $$PeersTableFilterComposer extends Composer<
        _$AppDatabase,
        $PeersTable> {
        $$PeersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
          ColumnFilters<String> get peerUid => $composableBuilder(
      column: $table.peerUid,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<DateTime> get lastSeen => $composableBuilder(
      column: $table.lastSeen,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<int> get rssi => $composableBuilder(
      column: $table.rssi,
      builder: (column) => 
      ColumnFilters(column));
      
ColumnFilters<String> get publicKeyFingerprint => $composableBuilder(
      column: $table.publicKeyFingerprint,
      builder: (column) => 
      ColumnFilters(column));
      
        }
      class $$PeersTableOrderingComposer extends Composer<
        _$AppDatabase,
        $PeersTable> {
        $$PeersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
          ColumnOrderings<String> get peerUid => $composableBuilder(
      column: $table.peerUid,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<DateTime> get lastSeen => $composableBuilder(
      column: $table.lastSeen,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<int> get rssi => $composableBuilder(
      column: $table.rssi,
      builder: (column) => 
      ColumnOrderings(column));
      
ColumnOrderings<String> get publicKeyFingerprint => $composableBuilder(
      column: $table.publicKeyFingerprint,
      builder: (column) => 
      ColumnOrderings(column));
      
        }
      class $$PeersTableAnnotationComposer extends Composer<
        _$AppDatabase,
        $PeersTable> {
        $$PeersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
          GeneratedColumn<String> get peerUid => $composableBuilder(
      column: $table.peerUid,
      builder: (column) => column);
      
GeneratedColumn<DateTime> get lastSeen => $composableBuilder(
      column: $table.lastSeen,
      builder: (column) => column);
      
GeneratedColumn<int> get rssi => $composableBuilder(
      column: $table.rssi,
      builder: (column) => column);
      
GeneratedColumn<String> get publicKeyFingerprint => $composableBuilder(
      column: $table.publicKeyFingerprint,
      builder: (column) => column);
      
        }
      class $$PeersTableTableManager extends RootTableManager    <_$AppDatabase,
    $PeersTable,
    Peer,
    $$PeersTableFilterComposer,
    $$PeersTableOrderingComposer,
    $$PeersTableAnnotationComposer,
    $$PeersTableCreateCompanionBuilder,
    $$PeersTableUpdateCompanionBuilder,
    (Peer,BaseReferences<_$AppDatabase,$PeersTable,Peer>),
    Peer,
    PrefetchHooks Function()
    > {
    $$PeersTableTableManager(_$AppDatabase db, $PeersTable table) : super(
      TableManagerState(
        db: db,
        table: table,
        createFilteringComposer: () => $$PeersTableFilterComposer($db: db,$table:table),
        createOrderingComposer: () => $$PeersTableOrderingComposer($db: db,$table:table),
        createComputedFieldComposer: () => $$PeersTableAnnotationComposer($db: db,$table:table),
        updateCompanionCallback: ({Value<String> peerUid = const Value.absent(),Value<DateTime> lastSeen = const Value.absent(),Value<int> rssi = const Value.absent(),Value<String> publicKeyFingerprint = const Value.absent(),Value<int> rowid = const Value.absent(),})=> PeersCompanion(peerUid: peerUid,lastSeen: lastSeen,rssi: rssi,publicKeyFingerprint: publicKeyFingerprint,rowid: rowid,),
        createCompanionCallback: ({required String peerUid,required DateTime lastSeen,required int rssi,Value<String> publicKeyFingerprint = const Value.absent(),Value<int> rowid = const Value.absent(),})=> PeersCompanion.insert(peerUid: peerUid,lastSeen: lastSeen,rssi: rssi,publicKeyFingerprint: publicKeyFingerprint,rowid: rowid,),
        withReferenceMapper: (p0) => p0
              .map(
                  (e) =>
                     (e.readTable(table), BaseReferences(db, table, e))
                  )
              .toList(),
        prefetchHooksCallback: null,
        ));
        }
    typedef $$PeersTableProcessedTableManager = ProcessedTableManager    <_$AppDatabase,
    $PeersTable,
    Peer,
    $$PeersTableFilterComposer,
    $$PeersTableOrderingComposer,
    $$PeersTableAnnotationComposer,
    $$PeersTableCreateCompanionBuilder,
    $$PeersTableUpdateCompanionBuilder,
    (Peer,BaseReferences<_$AppDatabase,$PeersTable,Peer>),
    Peer,
    PrefetchHooks Function()
    >;class $AppDatabaseManager {
final _$AppDatabase _db;
$AppDatabaseManager(this._db);
$$AttendanceProofsTableTableManager get attendanceProofs => $$AttendanceProofsTableTableManager(_db, _db.attendanceProofs);
$$MessageRecordsTableTableManager get messageRecords => $$MessageRecordsTableTableManager(_db, _db.messageRecords);
$$SosRecordsTableTableManager get sosRecords => $$SosRecordsTableTableManager(_db, _db.sosRecords);
$$SeenPacketsTableTableManager get seenPackets => $$SeenPacketsTableTableManager(_db, _db.seenPackets);
$$PeersTableTableManager get peers => $$PeersTableTableManager(_db, _db.peers);
}
