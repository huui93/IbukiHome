import 'dart:convert';
import 'dart:io';

import 'package:ibukihome/data/remote/dto/api_error_dto.dart';
import 'package:ibukihome/data/remote/dto/capabilities_response_dto.dart';
import 'package:ibukihome/data/remote/dto/dto_readers.dart';
import 'package:ibukihome/data/remote/dto/health_response_dto.dart';
import 'package:ibukihome/data/remote/dto/project_detail_dto.dart';
import 'package:ibukihome/data/remote/dto/project_summary_dto.dart';
import 'package:ibukihome/data/remote/dto/segment_dto.dart';

Map<String, dynamic> fixtureJson(String name) {
  final text = File('test/fixtures/remote_api/v1/$name').readAsStringSync();
  return Map<String, dynamic>.from(jsonDecode(text) as Map);
}

HealthResponseDto healthFixture() {
  return HealthResponseDto.fromJson(fixtureJson('health_response.json'));
}

CapabilitiesResponseDto capabilitiesFixture() {
  return CapabilitiesResponseDto.fromJson(
    fixtureJson('capabilities_response.json'),
  );
}

List<ProjectSummaryDto> projectListFixture() {
  final json = fixtureJson('project_list_response.json');
  return [
    for (final item in readRequiredList(json, 'items', 'ProjectListResponse'))
      ProjectSummaryDto.fromJson(requireObject(item, 'ProjectSummary')),
  ];
}

ProjectDetailDto projectDetailFixture() {
  return ProjectDetailDto.fromJson(fixtureJson('project_detail_response.json'));
}

List<SegmentDto> segmentListFixture() {
  final json = fixtureJson('segment_list_response.json');
  return [
    for (final item in readRequiredList(json, 'items', 'SegmentListResponse'))
      SegmentDto.fromJson(requireObject(item, 'Segment')),
  ];
}

ApiErrorDto apiErrorFixture() {
  return ApiErrorDto.fromJson(fixtureJson('api_error.json'));
}
