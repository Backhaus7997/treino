# Design Decisions

Documento de referencia con la imagen de diseño definitiva de cada módulo de TREINO (App Alumno, Trainer App y Trainer Web). Las imágenes son la **fuente de verdad** del diseño — la implementación debe matchear exactamente lo que muestran.

---

## Navigation bars (fijas en toda la UI)

Las barras de navegación deben quedar **fijas en toda la app**: el contenido scrollea por debajo, la barra permanece visible siempre. Su movimiento y animación siguen el patrón **liquid glass** implementado en [`lib/core/widgets/treino_bottom_bar.dart`](../lib/core/widgets/treino_bottom_bar.dart) (frosted blur + pill highlight con gradient + `AnimatedPositioned` al cambiar de tab).

### App Alumno — Bottom Bar

![Bottom Bar App Alumno](./app-alumno/screens/bottombar/bottombar.png)

### App Trainer — Bottom Bar

![Bottom Bar App Trainer](./app-trainer/screens/bottombar/bottombar.png)

### Web Trainer — Sidebar

![Sidebar Web Trainer](./web-trainer/screens/sidebar/sidebar.png)

---

## App Alumno

### Splash

![Splash](./app-alumno/screens/splash/splash.png)

---

### Welcome

![Welcome](./app-alumno/screens/welcome/welcome.png)

---

### Login

![Login](./app-alumno/screens/login/login.png)

---

### Register

![Register](./app-alumno/screens/register/register.png)

---

### Forgot Password

![Forgot Password](./app-alumno/screens/forgot-password/forgot-password.png)

---

### Profile Setup

![Profile Setup 1](./app-alumno/screens/profile-setup/profile-setup-1.png)
![Profile Setup 2](./app-alumno/screens/profile-setup/profile-setup-2.png)
![Profile Setup 3](./app-alumno/screens/profile-setup/profile-setup-3.png)
![Profile Setup 4](./app-alumno/screens/profile-setup/profile-setup-4.png)

---

### Home

#### Card "Empezar entrenamiento"

![Empezar entrenamiento](./app-alumno/screens/home/empezar-entrenamiento.png)

#### Card "Esta semana"

![Esta semana](./app-alumno/screens/home/esta-semana.png)

---

### Insights

![Insights](./app-alumno/screens/insights/insights.png)

---

### Entrenamiento

#### Tu rutina

![Tu rutina](./app-alumno/screens/entrenamiento/tu-rutina.png)

#### Plantillas

![Plantillas](./app-alumno/screens/entrenamiento/plantillas.png)

#### Expandir Plantillas

![Expandir Plantillas](./app-alumno/screens/entrenamiento/expandir-plantilla.png)

#### Historial

![Historial](./app-alumno/screens/entrenamiento/historial.png)

#### Expandir Historial

![Expandir Historial](./app-alumno/screens/entrenamiento/expandir-historial.png)

---

### Crear Rutina

![Crear Rutina](./app-alumno/screens/crear-rutina/crear-rutina.png)

---

### Detalle Rutina

#### Sesión del día

![Sesión del día](./app-alumno/screens/detalle-rutina/sesion-dia.png)

#### Detalle Ejercicio

![Detalle Ejercicio](./app-alumno/screens/detalle-rutina/detalle-ejercicio.png)

#### Resumen post-entreno

![Resumen post-entreno](./app-alumno/screens/detalle-rutina/post-entreno.png)

---

### Feed

![Feed](./app-alumno/screens/feed/feed.png)

#### Card "Público"

![Card Público](./app-alumno/screens/feed/feed-publico.png)

---

### Perfil Propio

![Perfil Propio](./app-alumno/screens/profile/profile.png)

---

### Coach Discovery

![Coach Discovery](./app-alumno/screens/coach/coach-discovery.png)

---

### Perfil Coach

![Perfil Coach](./app-alumno/screens/coach/coach-profile.png)

---

### Check-in

![Check-in](./app-alumno/screens/check-in/check-in.png)

---

## Trainer Web

### Dashboard

#### Welcome card

![Welcome card](./web-trainer/screens/dashboard/welcome-card.png)

#### Resto de cards

![Resto de cards](./web-trainer/screens/dashboard/resto-cards.png)

---

### Alumnos

#### Vista general

![Vista general](./web-trainer/screens/alumnos/view-general.png)

#### Resumen

![Resumen](./web-trainer/screens/alumnos/resumen.png)

#### Entrenamiento

![Entrenamiento](./web-trainer/screens/alumnos/entrenamiento.png)

#### Nutrición

![Nutrición](./web-trainer/screens/alumnos/nutricion.png)

#### Progreso

![Progreso](./web-trainer/screens/alumnos/progreso.png)

#### Historial

![Historial](./web-trainer/screens/alumnos/historial.png)

#### Notas Privadas

![Notas Privadas](./web-trainer/screens/alumnos/notas-privadas.png)

#### Archivos

![Archivos](./web-trainer/screens/alumnos/archivos.png)

---

### Solicitudes

#### Vista general

![Solicitudes — Vista general](./web-trainer/screens/solicitudes/view-general.png)

#### Detalles

![Solicitudes — Detalles](./web-trainer/screens/solicitudes/detalles.png)

---

### Rutina

![Rutina](./web-trainer/screens/rutina/rutina.png)

---

### Nutrición

![Nutrición](./web-trainer/screens/nutricion/nutricion.png)

#### Meta diaria

![Meta diaria](./web-trainer/screens/nutricion/meta-diaria.png)

---

### Biblioteca

#### Ejercicios

![Ejercicios](./web-trainer/screens/biblioteca/ejercicios.png)

#### Alimentos

![Alimentos](./web-trainer/screens/biblioteca/alimentos.png)

#### Template Rutina

![Template Rutina](./web-trainer/screens/biblioteca/template-rutina.png)

#### Template Nutrición

![Template Nutrición](./web-trainer/screens/biblioteca/template-nutricion.png)

---

### Chat

![Chat](./web-trainer/screens/chat/chat.png)

---

### Pagos

![Pagos](./web-trainer/screens/pagos/pagos.png)

---

### Planes Comerciales

#### Vista general

![Planes Comerciales — Vista general](./web-trainer/screens/planes-comerciales/view-general.png)

#### Crear plan

![Crear plan](./web-trainer/screens/planes-comerciales/crear-plan.png)

---

### Perfil Público

![Perfil Público](./web-trainer/screens/perfil-publico/perfil-publico.png)

---

### Ajustes

#### Cuenta

![Cuenta](./web-trainer/screens/ajustes/cuenta.png)

#### Notificaciones

![Notificaciones](./web-trainer/screens/ajustes/notificaciones.png)

#### Facturación Treino

![Facturación Treino](./web-trainer/screens/ajustes/facturacion-treino.png)

#### Datos y Privacidad

![Datos y Privacidad](./web-trainer/screens/ajustes/datos-privacidad.png)

---

## Trainer App

### Hoy (Dashboard)

![Dashboard 1](./app-trainer/screens/dashboard/dashboard-1.png)
![Dashboard 2](./app-trainer/screens/dashboard/dashboard-2.png)

---

### Chat

#### Vista general

![Chat — Vista general](./app-trainer/screens/chat/view-general.png)

#### Chat privado

![Chat privado](./app-trainer/screens/chat/chat-privado.png)

---

### Alumnos

![Alumnos 1](./app-trainer/screens/alumnos/alumnos-1.png)
![Alumnos 2](./app-trainer/screens/alumnos/alumnos-2.png)
![Alumnos 3](./app-trainer/screens/alumnos/alumnos-3.png)

---

### Actividad

![Actividad](./app-trainer/screens/actividad/actividad.png)

---

### Mi Perfil

![Mi Perfil](./app-trainer/screens/perfil/perfil.png)
