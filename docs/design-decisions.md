# Design Decisions — App Alumno

Documento de referencia sobre qué proyecto de Claude Design ganó en cada módulo, y qué modificaciones (si aplican) deben hacerse al implementar.

---

## Resumen por módulo

| Módulo | Proyecto | Ajustes |
|---|---|---|
| Splash | Mateo | Sin cambios |
| Welcome | Llanca | Sin cambios |
| Login | Joaco | Sin cambios |
| Register | Joaco | Sin cambios |
| Forgot Password | Mateo | Sin cambios |
| Profile Setup | Mateo | Sin cambios |
| Home — Card "Empezar entrenamiento" | Joaco | Sin cambios |
| Home — Card "Esta semana" | Llanca | Sin cambios |
| Home — Card "Semana y mes" | Mateo | Sacar volumen |
| Insights | Mateo | Sin cambios |
| Entrenamiento — Tu rutina | Joaco | Solo mostrar la rutina actual |
| Entrenamiento — Plantillas | Joaco | Sin cambios |
| Entrenamiento — Expandir Plantillas | Mateo | Sin cambios |
| Entrenamiento — Historial | Joaco | Sin cambios |
| Entrenamiento — Expandir Historial | Mateo | Sin cambios |
| Crear Rutina | Joaco | Sin cambios |
| Detalle Rutina — Sesión del día | Joaco | Sin cambios |
| Detalle Rutina — Detalle Ejercicio | Mateo | Sin cambios |
| Detalle Rutina — Resumen post-entreno | Mateo | Sin cambios |
| Feed | Joaco | Sin cambios |
| Feed — Card "Público" | Mateo | Sin cambios |
| Perfil Propio | Joaco | Sin cambios |
| Coach Discovery | Joaco | Sin cambios |
| Perfil Coach | Joaco | Sin cambios |
| Check-in | Mateo | Sin cambios |

---

## Detalle por módulo

### Splash
- **Origen:** Proyecto Mateo
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-mateo.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-mateo.html)
- **Modificaciones:** Ninguna

![Splash](./app-alumno/screens/splash/splash.png)

---

### Welcome
- **Origen:** Proyecto Llanca
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-llanca.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-llanca.html)
- **Modificaciones:** Ninguna

![Welcome](./app-alumno/screens/welcome/welcome.png)

---

### Login
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-joaco.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-joaco.html)
- **Modificaciones:** Ninguna

![Login](./app-alumno/screens/login/login.png)

---

### Register
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-joaco.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-joaco.html)
- **Modificaciones:** Ninguna

![Register](./app-alumno/screens/register/register.png)

---

### Forgot Password
- **Origen:** Proyecto Mateo
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-mateo.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-mateo.html)
- **Modificaciones:** Ninguna

![Forgot Password](./app-alumno/screens/forgot-password/forgot-password.png)

---

### Profile Setup
- **Origen:** Proyecto Mateo
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-mateo.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-mateo.html)
- **Modificaciones:** Ninguna

![Profile Setup 1](./app-alumno/screens/profile-setup/profile-setup-1.png)
![Profile Setup 2](./app-alumno/screens/profile-setup/profile-setup-2.png)
![Profile Setup 3](./app-alumno/screens/profile-setup/profile-setup-3.png)
![Profile Setup 4](./app-alumno/screens/profile-setup/profile-setup-4.png)

---

### Home

> Este módulo es una **composición** de cards tomadas de los 3 proyectos. No existe un único screen de referencia.

#### Card "Empezar entrenamiento"
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-joaco.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-joaco.html)
- **Modificaciones:** Ninguna

![Empezar entrenamiento](./app-alumno/screens/home/empezar-entrenamiento.png)

#### Card "Esta semana"
- **Origen:** Proyecto Llanca
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-llanca.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-llanca.html)
- **Modificaciones:** Ninguna

![Esta semana](./app-alumno/screens/home/esta-semana.png)

---

### Insights
- **Origen:** Proyecto Mateo
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-mateo.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-mateo.html)
- **Modificaciones:** Ninguna

![Insights](./app-alumno/screens/insights/insights.png)

---

### Entrenamiento

#### Tu rutina
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-joaco.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-joaco.html)
- **Modificaciones:** Solo debe mostrarse la rutina actual

![Tu rutina](./app-alumno/screens/entrenamiento/tu-rutina.png)

#### Plantillas
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-joaco.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-joaco.html)
- **Modificaciones:** Ninguna

![Plantillas](./app-alumno/screens/entrenamiento/plantillas.png)

#### Expandir Plantillas
- **Origen:** Proyecto Mateo
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-mateo.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-mateo.html)
- **Modificaciones:** Ninguna

![Expandir Plantillas](./app-alumno/screens/entrenamiento/expandir-plantilla.png)

#### Historial
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-joaco.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-joaco.html)
- **Modificaciones:** Ninguna

![Historial](./app-alumno/screens/entrenamiento/historial.png)

#### Expandir Historial
- **Origen:** Proyecto Mateo
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-mateo.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-mateo.html)
- **Modificaciones:** Ninguna

![Expandir Historial](./app-alumno/screens/entrenamiento/expandir-historial.png)

---

### Crear Rutina
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-joaco.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-joaco.html)
- **Modificaciones:** Ninguna

![Crear Rutina](./app-alumno/screens/crear-rutina/crear-rutina.png)

---

### Detalle Rutina

#### Sesión del día
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-joaco.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-joaco.html)
- **Modificaciones:** Ninguna

![Sesión del día](./app-alumno/screens/detalle-rutina/sesion-dia.png)

#### Detalle Ejercicio
- **Origen:** Proyecto Mateo
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-mateo.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-mateo.html)
- **Modificaciones:** Ninguna

![Detalle Ejercicio](./app-alumno/screens/detalle-rutina/detalle-ejercicio.png)

#### Resumen post-entreno
- **Origen:** Proyecto Mateo
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-mateo.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-mateo.html)
- **Modificaciones:** Ninguna

![Resumen post-entreno](./app-alumno/screens/detalle-rutina/post-entreno.png)

---

### Feed
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-joaco.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-joaco.html)
- **Modificaciones:** Ninguna

![Feed](./app-alumno/screens/feed/feed.png)

#### Card "Público"
- **Origen:** Proyecto Mateo
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-mateo.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-mateo.html)
- **Modificaciones:** Ninguna

![Card Público](./app-alumno/screens/feed/feed-publico.png)

---

### Perfil Propio
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-joaco.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-joaco.html)
- **Modificaciones:** Ninguna

![Perfil Propio](./app-alumno/screens/profile/profile.png)

---

### Coach Discovery
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-joaco.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-joaco.html)
- **Modificaciones:** Ninguna

![Coach Discovery](./app-alumno/screens/coach/coach-discovery.png)

---

### Perfil Coach
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-joaco.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-joaco.html)
- **Modificaciones:** Ninguna

![Perfil Coach](./app-alumno/screens/coach/coach-profile.png)

---

### Check-in
- **Origen:** Proyecto Mateo
- **Referencia:** [`screens/full-projects/proyecto-app-alumno-mateo.html`](./app-alumno/screens/full-projects/proyecto-app-alumno-mateo.html)
- **Modificaciones:** Ninguna

![Check-in](./app-alumno/screens/check-in/check-in.png)


# Design Decisions — Trainer (Web + App)

Documento de referencia sobre qué proyecto de Claude Design ganó en cada módulo de Trainer, y qué modificaciones (si aplican) deben hacerse al implementar.

---

## Trainer Web

### Resumen por módulo

| Módulo | Proyecto | Ajustes |
|---|---|---|
| Dashboard — Welcome card | Joaco | Sin cambios |
| Dashboard — Resto de cards | Llanca | Sin cambios |
| Alumnos — Vista general | Joaco | Sin cambios |
| Alumnos — Resumen | Llanca | Sin cambios |
| Alumnos — Entrenamiento | Llanca | Sin cambios |
| Alumnos — Nutrición | Llanca | Sin cambios |
| Alumnos — Progreso | Joaco | Revisar qué incluir |
| Alumnos — Historial | Joaco | Sin cambios |
| Alumnos — Notas Privadas | Joaco | Sin cambios |
| Alumnos — Archivos | Joaco | Sin cambios |
| Solicitudes — Vista general | Llanca | Sin cambios |
| Solicitudes — Detalles | Llanca | Sin cambios |
| Rutina | Joaco | Sin cambios |
| Nutrición | Joaco | Agregar configuración por días o semanas |
| Nutrición — Meta diaria | Llanca | Sin cambios |
| Biblioteca — Ejercicios | Llanca | Sin cambios |
| Biblioteca — Alimentos | Llanca | Sin cambios |
| Biblioteca — Template Rutina | Llanca | Sin cambios |
| Biblioteca — Template Nutrición | Llanca | Sin cambios |
| Chat | Joaco | Sacar el panel de "acciones" del costado |
| Pagos | Joaco | Sin cambios |
| Planes Comerciales — Vista general | Llanca | Sin cambios |
| Planes Comerciales — Crear plan | Llanca | Sin cambios |
| Perfil Público | Joaco | Sin cambios |
| Ajustes — Cuenta | Llanca | Sin cambios |
| Ajustes — Notificaciones | Llanca | Sin cambios |
| Ajustes — Facturación Treino | Llanca | Sin cambios |
| Ajustes — Datos y Privacidad | Llanca | Sin cambios |

---

### Detalle por módulo

#### Dashboard

> Composición de cards de 2 proyectos.

##### Welcome card
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-joaco.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-joaco.html)
- **Modificaciones:** Ninguna

![Welcome card](./web-trainer/screens/dashboard/welcome-card.png)

##### Resto de cards
- **Origen:** Proyecto Llanca
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-llanca.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-llanca.html)
- **Modificaciones:** Ninguna

![Resto de cards](./web-trainer/screens/dashboard/resto-cards.png)

---

#### Alumnos

##### Vista general
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-joaco.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-joaco.html)
- **Modificaciones:** Ninguna

![Vista general](./web-trainer/screens/alumnos/view-general.png)

##### Resumen
- **Origen:** Proyecto Llanca
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-llanca.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-llanca.html)
- **Modificaciones:** Ninguna

![Resumen](./web-trainer/screens/alumnos/resumen.png)

##### Entrenamiento
- **Origen:** Proyecto Llanca
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-llanca.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-llanca.html)
- **Modificaciones:** Ninguna

![Entrenamiento](./web-trainer/screens/alumnos/entrenamiento.png)

##### Nutrición
- **Origen:** Proyecto Llanca
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-llanca.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-llanca.html)
- **Modificaciones:** Ninguna

![Nutrición](./web-trainer/screens/alumnos/nutricion.png)

##### Progreso
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-joaco.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-joaco.html)
- **Modificaciones:** Revisar qué incluir en este módulo (definir antes de implementar)

![Progreso](./web-trainer/screens/alumnos/progreso.png)

##### Historial
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-joaco.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-joaco.html)
- **Modificaciones:** Ninguna

![Historial](./web-trainer/screens/alumnos/historial.png)

##### Notas Privadas
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-joaco.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-joaco.html)
- **Modificaciones:** Ninguna

![Notas Privadas](./web-trainer/screens/alumnos/notas-privadas.png)

##### Archivos
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-joaco.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-joaco.html)
- **Modificaciones:** Ninguna

![Archivos](./web-trainer/screens/alumnos/archivos.png)

---

#### Solicitudes

##### Vista general
- **Origen:** Proyecto Llanca
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-llanca.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-llanca.html)
- **Modificaciones:** Ninguna

![Solicitudes — Vista general](./web-trainer/screens/solicitudes/view-general.png)

##### Detalles
- **Origen:** Proyecto Llanca
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-llanca.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-llanca.html)
- **Modificaciones:** Ninguna

![Solicitudes — Detalles](./web-trainer/screens/solicitudes/detalles.png)

---

#### Rutina
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-joaco.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-joaco.html)
- **Modificaciones:** Ninguna

![Rutina](./web-trainer/screens/rutina/rutina.png)

---

#### Nutrición
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-joaco.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-joaco.html)
- **Modificaciones:** Agregar la posibilidad de configurar por días o semanas

![Nutrición](./web-trainer/screens/nutricion/nutricion.png)

##### Meta diaria
- **Origen:** Proyecto Llanca
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-llanca.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-llanca.html)
- **Modificaciones:** Ninguna

![Meta diaria](./web-trainer/screens/nutricion/meta-diaria.png)

---

#### Biblioteca

##### Ejercicios
- **Origen:** Proyecto Llanca
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-llanca.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-llanca.html)
- **Modificaciones:** Ninguna

![Ejercicios](./web-trainer/screens/biblioteca/ejercicios.png)

##### Alimentos
- **Origen:** Proyecto Llanca
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-llanca.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-llanca.html)
- **Modificaciones:** Ninguna

![Alimentos](./web-trainer/screens/biblioteca/alimentos.png)

##### Template Rutina
- **Origen:** Proyecto Llanca
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-llanca.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-llanca.html)
- **Modificaciones:** Ninguna

![Template Rutina](./web-trainer/screens/biblioteca/template-rutina.png)

##### Template Nutrición
- **Origen:** Proyecto Llanca
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-llanca.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-llanca.html)
- **Modificaciones:** Ninguna

![Template Nutrición](./web-trainer/screens/biblioteca/template-nutricion.png)

---

#### Chat
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-joaco.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-joaco.html)
- **Modificaciones:** Sacar el panel de "acciones" del costado

![Chat](./web-trainer/screens/chat/chat.png)

---

#### Pagos
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-joaco.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-joaco.html)
- **Modificaciones:** Ninguna

![Pagos](./web-trainer/screens/pagos/pagos.png)

---

#### Planes Comerciales

##### Vista general
- **Origen:** Proyecto Llanca
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-llanca.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-llanca.html)
- **Modificaciones:** Ninguna

![Planes Comerciales — Vista general](./web-trainer/screens/planes-comerciales/view-general.png)

##### Crear plan
- **Origen:** Proyecto Llanca
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-llanca.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-llanca.html)
- **Modificaciones:** Ninguna

![Crear plan](./web-trainer/screens/planes-comerciales/crear-plan.png)

---

#### Perfil Público
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-joaco.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-joaco.html)
- **Modificaciones:** Ninguna

![Perfil Público](./web-trainer/screens/perfil-publico/perfil-publico.png)

---

#### Ajustes

##### Cuenta
- **Origen:** Proyecto Llanca
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-llanca.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-llanca.html)
- **Modificaciones:** Ninguna

![Cuenta](./web-trainer/screens/ajustes/cuenta.png)

##### Notificaciones
- **Origen:** Proyecto Llanca
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-llanca.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-llanca.html)
- **Modificaciones:** Ninguna

![Notificaciones](./web-trainer/screens/ajustes/notificaciones.png)

##### Facturación Treino
- **Origen:** Proyecto Llanca
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-llanca.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-llanca.html)
- **Modificaciones:** Ninguna

![Facturación Treino](./web-trainer/screens/ajustes/facturacion-treino.png)

##### Datos y Privacidad
- **Origen:** Proyecto Llanca
- **Referencia:** [`screens/full-projects/proyecto-web-trainer-llanca.html`](./web-trainer/screens/full-projects/proyecto-web-trainer-llanca.html)
- **Modificaciones:** Ninguna

![Datos y Privacidad](./web-trainer/screens/ajustes/datos-privacidad.png)

---

## Trainer App

### Resumen por módulo

| Módulo | Proyecto | Ajustes |
|---|---|---|
| Hoy (Dashboard) | Llanca | Sin cambios |
| Chat — Vista general | Llanca | Sin cambios |
| Chat — Chat privado | Joaco | Sin cambios |
| Alumnos | Llanca | Sin cambios |
| Actividad | Joaco | Sin cambios |
| Mi Perfil | Llanca | Sin cambios |

---

### Detalle por módulo

#### Hoy (Dashboard)
- **Origen:** Proyecto Mateo
- **Referencia:** [`screens/full-projects/proyecto-app-trainer-mateo.html`](./app-trainer/screens/full-projects/proyecto-app-trainer-mateo.html)
- **Modificaciones:** Ninguna

![Dashboard 1](./app-trainer/screens/dashboard/dashboard-1.png)
![Dashboard 2](./app-trainer/screens/dashboard/dashboard-2.png)

---

#### Chat

##### Vista general
- **Origen:** Proyecto Mateo
- **Referencia:** [`screens/full-projects/proyecto-app-trainer-mateo.html`](./app-trainer/screens/full-projects/proyecto-app-trainer-mateo.html)
- **Modificaciones:** Ninguna

![Chat — Vista general](./app-trainer/screens/chat/view-general.png)

##### Chat privado
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-app-trainer-joaco.html`](./app-trainer/screens/full-projects/proyecto-app-trainer-joaco.html)
- **Modificaciones:** Ninguna

![Chat privado](./app-trainer/screens/chat/chat-privado.png)

---

#### Alumnos
- **Origen:** Proyecto Mateo
- **Referencia:** [`screens/full-projects/proyecto-app-trainer-mateo.html`](./app-trainer/screens/full-projects/proyecto-app-trainer-mateo.html)
- **Modificaciones:** Ninguna

![Alumnos 1](./app-trainer/screens/alumnos/alumnos-1.png)
![Alumnos 2](./app-trainer/screens/alumnos/alumnos-2.png)
![Alumnos 3](./app-trainer/screens/alumnos/alumnos-3.png)

---

#### Actividad
- **Origen:** Proyecto Joaco
- **Referencia:** [`screens/full-projects/proyecto-app-trainer-joaco.html`](./app-trainer/screens/full-projects/proyecto-app-trainer-joaco.html)
- **Modificaciones:** Ninguna

![Actividad](./app-trainer/screens/actividad/actividad.png)

---

#### Mi Perfil
- **Origen:** Proyecto Mateo
- **Referencia:** [`screens/full-projects/proyecto-app-trainer-mateo.html`](./app-trainer/screens/full-projects/proyecto-app-trainer-mateo.html)
- **Modificaciones:** Ninguna

![Mi Perfil](./app-trainer/screens/perfil/perfil.png)