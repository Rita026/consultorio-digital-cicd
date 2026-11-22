// Providers globales para todas las pruebas unitarias.
// Los componentes usan RouterLink/ActivatedRoute y algunos navegan
// (ej. a /login/paciente al cerrar sesión). Se registra un router con
// una ruta comodín que acepta cualquier URL para que esas navegaciones
// no generen errores en el entorno de pruebas.
import { Component } from '@angular/core';
import { provideRouter } from '@angular/router';

@Component({ selector: 'app-test-empty', template: '' })
class TestEmptyPage {}

export default [provideRouter([{ path: '**', component: TestEmptyPage }])];
