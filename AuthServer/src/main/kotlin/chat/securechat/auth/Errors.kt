package chat.securechat.auth

import io.ktor.http.HttpStatusCode

/**
 * `error` is a machine-readable code, never display text — mirrors the
 * convention already used elsewhere in this project's API docs
 * (WebSocketServer/mock's registration API), kept here for consistency even
 * though that server is a separate, unrelated prototype.
 */
class ApiException(val status: HttpStatusCode, val code: String) : RuntimeException(code)

fun badRequest(code: String): Nothing = throw ApiException(HttpStatusCode.BadRequest, code)
fun unauthorized(code: String): Nothing = throw ApiException(HttpStatusCode.Unauthorized, code)
fun notFound(code: String): Nothing = throw ApiException(HttpStatusCode.NotFound, code)
