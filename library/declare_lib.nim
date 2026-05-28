import ffi
import src/chat/client
import waku/waku_mix/logos_core_client as mix_rln_client

declareLibrary("logoschat")

proc set_event_callback(
    ctx: ptr FFIContext[ChatClient],
    callback: FFICallBack,
    userData: pointer
) {.dynlib, exportc, cdecl.} =
  ctx[].eventCallback = cast[pointer](callback)
  ctx[].eventUserData = userData

proc chat_set_rln_fetcher(
    ctx: ptr FFIContext[ChatClient], fetcher: mix_rln_client.RlnFetcherFunc, fetcherData: pointer
) {.dynlib, exportc, cdecl.} =
  if fetcher.isNil:
    echo "error: nil fetcher in chat_set_rln_fetcher"
    return
  mix_rln_client.setRlnFetcher(fetcher, fetcherData)

proc chat_set_rln_config(
    ctx: ptr FFIContext[ChatClient], configAccountId: cstring, leafIndex: cint
): cint {.dynlib, exportc, cdecl.} =
  if configAccountId.isNil:
    return RET_ERR
  mix_rln_client.setRlnConfig($configAccountId, leafIndex.int)
  return RET_OK

proc chat_set_rln_identity(
    ctx: ptr FFIContext[ChatClient], idSecretHashHex: cstring
) {.dynlib, exportc, cdecl.} =
  if idSecretHashHex.isNil:
    return
  mix_rln_client.setRlnIdentity($idSecretHashHex)

proc chat_push_roots(
    ctx: ptr FFIContext[ChatClient], rootsJson: cstring
) {.dynlib, exportc, cdecl.} =
  if rootsJson.isNil:
    return
  mix_rln_client.pushRoots($rootsJson)

proc chat_push_proof(
    ctx: ptr FFIContext[ChatClient], proofJson: cstring
) {.dynlib, exportc, cdecl.} =
  if proofJson.isNil:
    return
  mix_rln_client.pushProof($proofJson)

