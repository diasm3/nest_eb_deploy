import { Controller, Get } from '@nestjs/common';
import { AppService } from './app.service';

@Controller()
export class AppController {
  constructor(private readonly appService: AppService) {}

  @Get()
  getHello(): string {
    return this.appService.getHello();
  }

  @Get()
  getHealth(): string {
    return 'OK';
  }

  @Get('health')
  healthCheck(): object {
    return { status: 'ok', timestamp: new Date().toISOString() };
  }
}
