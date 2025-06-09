import { Controller, Get } from '@nestjs/common';

// app.controller.ts
@Controller()
export class AppController {
  @Get()
  helloworld(): string {
    return 'hello world';
  }

  @Get()
  helloworld2(): string {
    return 'hello world';
  }

  @Get()
  getRoot(): string {
    return 'NestJS App is running!';
  }

  @Get('health')
  healthCheck() {
    return {
      status: 'ok',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
    };
  }
}
