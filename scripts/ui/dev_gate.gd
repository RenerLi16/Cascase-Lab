class_name DevGate
extends RefCounted

# Developer sandbox access for instructor/demo builds.
#
# This is a convenience gate, not authentication: a password checked inside a
# downloadable web game can be inspected or bypassed. It unlocks only the local
# sandbox (level picker, hidden-state inspector). It grants no backend, export,
# participant-record or AI access, and it is unrelated to the study access code.
#
# Only a salted SHA-256 digest is stored. The plain password is never displayed,
# logged, placed in a URL, or kept after the check.
const SALT := "cascade-dev-gate-v1:"
const DIGEST := "3d565e219b964d0e969ce88fa8b6fd66aa478e3e7e68f87baa0051639aca79ff"

# Memory only: a refresh or restart locks it again.
static var unlocked := false

# The sandbox entry exists in development and instructor builds. A participant
# export never offers it, whatever else is configured.
static func available() -> bool:
	if OS.has_feature("participant"): return false
	return OS.has_feature("instructor") or bool(ProjectSettings.get_setting("cascade/development_access",true))

# Web and instructor builds ask for the password. The offline editor/native
# development build keeps its existing direct access.
static func password_required() -> bool:
	return OS.has_feature("web") or OS.has_feature("instructor") or bool(ProjectSettings.get_setting("cascade/dev_password_required",false))

static func is_open() -> bool:
	return available() and (unlocked or not password_required())

static func try_unlock(candidate: String) -> bool:
	if not available(): return false
	var ok := (SALT + candidate).sha256_text() == DIGEST
	if ok: unlocked = true
	return ok

static func lock() -> void:
	unlocked = false
