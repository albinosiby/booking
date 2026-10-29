import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from "@nestjs/common";
import { AdminMcpAuthService, voiceScopeForRequest } from "./admin-mcp-auth";

@Injectable()
export class AdminMcpGuard implements CanActivate {
  constructor(private readonly auth: AdminMcpAuthService) {}
  async canActivate(context: ExecutionContext) {
    const req = context.switchToHttp().getRequest();
    const scope = voiceScopeForRequest(req.method, req.path);
    if (!scope)
      throw new UnauthorizedException("Admin MCP endpoint is not allowed.");
    req.actor = await this.auth.authenticate(req.headers.authorization, scope);
    return true;
  }
}
