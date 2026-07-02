// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'athlete_file.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$AthleteFileImpl _$$AthleteFileImplFromJson(Map<String, dynamic> json) =>
    _$AthleteFileImpl(
      id: json['id'] as String,
      trainerId: json['trainerId'] as String,
      athleteId: json['athleteId'] as String,
      fileName: json['fileName'] as String,
      kind: $enumDecode(_$AthleteFileKindEnumMap, json['kind']),
      contentType: json['contentType'] as String,
      sizeBytes: (json['sizeBytes'] as num).toInt(),
      storagePath: json['storagePath'] as String,
      downloadUrl: json['downloadUrl'] as String,
      uploadedAt:
          const TimestampConverter().fromJson(json['uploadedAt'] as Timestamp),
    );

Map<String, dynamic> _$$AthleteFileImplToJson(_$AthleteFileImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'trainerId': instance.trainerId,
      'athleteId': instance.athleteId,
      'fileName': instance.fileName,
      'kind': _$AthleteFileKindEnumMap[instance.kind]!,
      'contentType': instance.contentType,
      'sizeBytes': instance.sizeBytes,
      'storagePath': instance.storagePath,
      'downloadUrl': instance.downloadUrl,
      'uploadedAt': const TimestampConverter().toJson(instance.uploadedAt),
    };

const _$AthleteFileKindEnumMap = {
  AthleteFileKind.pdf: 'pdf',
  AthleteFileKind.image: 'image',
  AthleteFileKind.other: 'other',
};
