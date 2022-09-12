%Doctor.Config{
  exception_moduledoc_required: true,
  failed: false,
  ignore_modules: [],
  ignore_paths: [
    ~s(lib/eidfs_web.ex),
    ~s(lib/eidfs_web/telemetry.ex),
    ~r(lib/eidfs_web/controllers/.*),
    ~r(lib/eidfs_web/views/.*),
    ~r(test/support/.*)
  ],
  min_module_doc_coverage: 80,
  min_module_spec_coverage: 80,
  min_overall_doc_coverage: 80,
  min_overall_spec_coverage: 80,
  moduledoc_required: false,
  raise: true,
  reporter: Doctor.Reporters.Full,
  struct_type_spec_required: true,
  umbrella: false
}
