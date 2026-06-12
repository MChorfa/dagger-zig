package supply_chain.governance

default allow := false

allow if {
    has_valid_type
    has_correct_subject
    is_secure_builder
    has_slsa_v1_build_definition
}

has_valid_type if {
    input._type == "https://in-toto.io/Statement/v1"
    input.predicateType == "https://slsa.dev/provenance/v1"
}

has_correct_subject if {
    some i
    input.subject[i].name == "sbom.spdx.json"
    count(input.subject[i].digest.sha256) == 64
}

is_secure_builder if {
    input.predicate.runDetails.builder.id == "https://dagger.io/engine"
}

has_slsa_v1_build_definition if {
    input.predicate.buildDefinition.buildType == "https://dagger.io/build/v1"
}
