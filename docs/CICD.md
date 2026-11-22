# Liberación y despliegue continuo — Consultorio Digital

Pipeline de CI/CD con **GitHub Actions** y **Vercel** para la aplicación Angular
del Consultorio Digital (backend en Supabase).

## Archivos del pipeline

| Requisito de la actividad | Archivo |
|---|---|
| Scripts del flujo de trabajo (pipeline) | `.github/workflows/pipeline-cicd.yml`, `.github/workflows/monitoreo.yml` |
| Scripts para la generación del entorno de liberación | `scripts/configurar-entorno-liberacion.sh` (una sola vez), `scripts/generar-entorno.sh` (en cada ejecución), `vercel.json` |
| Scripts de pruebas en el entorno de liberación | `scripts/pruebas-humo.sh` (+ pruebas unitarias: `npm run test:ci`) |
| Scripts para la generación del despliegue | `scripts/desplegar.sh`, `scripts/liberar.sh` (liberación y rollback) |

## Flujo

```
push a main ──► 1 Integración ──► 2 Staging ──► 3 Pruebas staging ──► 4 Candidato producción ──► 5 Liberación
                (tests + build)   (Vercel        (pruebas de humo)     (deploy sin dominio +       (promote +
                                   Preview)                             pruebas de humo)             verificación)

pull request ──► 1 ──► 2 ──► 3   (cada PR tiene su propio entorno de liberación)
```

Si cualquier etapa falla, las siguientes no se ejecutan y producción no cambia.

## Configuración (una sola vez)

### Requisitos
- Cuenta de [Vercel](https://vercel.com) (puedes registrarte con GitHub).
- Node.js 22, Git, [GitHub CLI](https://cli.github.com) y Vercel CLI: `npm i -g vercel`.
- En Windows, ejecuta los scripts desde **Git Bash**.

### Opción A: con el script

```bash
bash scripts/configurar-entorno-liberacion.sh consultorio-digital-cicd
```

El script crea el proyecto en Vercel, activa el bypass de protección para las
pruebas automáticas, crea los entornos `staging` y `production` en GitHub y guarda
los secrets. Solo te pide el token de Vercel
(se crea en <https://vercel.com/account/tokens>) y confirmar los datos de Supabase.

### Opción B: manual

1. `vercel link` en la raíz del repo → crea el proyecto. Los ids quedan en `.vercel/project.json`.
2. En Vercel → *Settings → Deployment Protection → Protection Bypass for Automation* → genera un secreto.
3. En GitHub → *Settings → Environments*: crea `staging` y `production`.
4. En GitHub → *Settings → Secrets and variables → Actions*:

| Tipo | Nombre | Valor |
|---|---|---|
| Secret | `VERCEL_TOKEN` | token de Vercel |
| Secret | `VERCEL_ORG_ID` | `orgId` de `.vercel/project.json` |
| Secret | `VERCEL_PROJECT_ID` | `projectId` de `.vercel/project.json` |
| Secret | `VERCEL_AUTOMATION_BYPASS_SECRET` | secreto del paso 2 |
| Secret | `SUPABASE_URL` | `https://<proyecto>.supabase.co` |
| Secret | `SUPABASE_ANON_KEY` | llave pública *anon* de Supabase |
| Variable | `PRODUCTION_URL` | `https://<proyecto>.vercel.app` |

### Primer despliegue
Haz push a `main` o ve a *Actions → Pipeline CI/CD → Run workflow*.

## Operación

- **Ver despliegues:** pestaña *Actions* del repo, o *Deployments* en Vercel.
- **Rollback:** *Actions → Pipeline CI/CD → Run workflow* y pon en `rollback_url` la
  URL de un despliegue anterior que funcionaba (se ve en Vercel → *Deployments*).
  También desde la terminal: `bash scripts/liberar.sh <url>`.
- **Aprobación manual antes de producción (opcional):** en GitHub → *Environments →
  production → Required reviewers*. Con eso el pipeline espera a que alguien apruebe
  antes de las etapas 4 y 5 (pasa de *despliegue continuo* a *entrega continua*).
- **Monitoreo:** el workflow `monitoreo.yml` revisa producción cada hora. Si falla,
  GitHub avisa por correo.

## Correr las pruebas localmente

```bash
npm ci
npm run test:ci                      # pruebas unitarias
bash scripts/pruebas-humo.sh https://<tu-despliegue>.vercel.app
```

> `scripts/generar-entorno.sh` sobrescribe `src/environments/environment.ts`. Si lo
> corres en tu computadora, regresa el archivo con `git checkout src/environments/environment.ts`.
