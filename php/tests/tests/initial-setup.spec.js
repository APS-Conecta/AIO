import { test, expect } from '@playwright/test';
import { writeFileSync } from 'node:fs'
import { logInToContainersPage } from './helpers.js';

// The es-CL suite (patch 090): every assertion the 060 sweep re-skinned now asserts the
// translated bytes the wizard actually renders. One assertion stays English ON PURPOSE —
// it asserts a PHP exception body (ConfigurationManager.php:1037), and the fork's zero-PHP
// rule keeps the 68 unreachable-PHP strings English. That line is the suite's living proof
// that the sweep never bled into php/src. (The IP refusal, the other one, is asserted in
// restore-instance.spec.js: with domain validation skipped, as here, patch 233 accepts an IP.)

test('Initial setup', async ({ page: setupPage }) => {
  test.setTimeout(10 * 60 * 1000)

  const containersPage = await logInToContainersPage(setupPage);

  // Accept example.com (requires disabled domain validation)
  await containersPage.locator('#domain').click();
  await containersPage.locator('#domain').fill('example.com');
  await containersPage.getByRole('button', { name: 'Enviar dominio' }).click();

  // The additional containers start off (patch 210) and the office is Euro-Office (patch 200)
  await expect(containersPage.locator('#talk')).not.toBeChecked()
  await expect(containersPage.getByRole('checkbox', { name: 'Whiteboard' })).not.toBeChecked()
  await expect(containersPage.getByRole('checkbox', { name: 'Imaginary' })).not.toBeChecked()
  await expect(containersPage.locator('#office-eurooffice')).toBeChecked()
  await containersPage.locator('#talk').check();
  await containersPage.getByRole('button', { name: 'Guardar cambios' }).last().click();
  await expect(containersPage.locator('#talk')).toBeChecked()
  await containersPage.locator('#talk').uncheck();
  await containersPage.getByRole('button', { name: 'Guardar cambios' }).last().click();
  await expect(containersPage.locator('#talk')).not.toBeChecked()

  // Reject invalid time zones (PHP-borne English: ConfigurationManager.php:1037 — stays, zero-PHP)
  await containersPage.locator('#timezone').click();
  await containersPage.locator('#timezone').fill('Invalid time zone');
  containersPage.once('dialog', dialog => {
    dialog.accept()
  });
  await containersPage.getByRole('button', { name: 'Enviar zona horaria' }).click();
  await expect(containersPage.locator('body')).toContainText('The entered timezone does not seem to be a valid timezone!');

  // Accept valid time zone
  await containersPage.locator('#timezone').click();
  await containersPage.locator('#timezone').fill('Europe/Berlin');
  containersPage.once('dialog', dialog => {
    dialog.accept()
  });
  await containersPage.getByRole('button', { name: 'Enviar zona horaria' }).click();

  // Start containers and wait for starting message
  await containersPage.getByRole('button', { name: 'Descargar e iniciar contenedores' }).click();
  await expect(containersPage.getByRole('main')).toContainText('Los contenedores se están iniciando', { timeout: 5 * 60 * 1000 });
  await expect(containersPage.getByRole('link', { name: 'Abrir APS Conecta Gestión ↗' })).toBeVisible({ timeout: 3 * 60 * 1000 });
  await expect(containersPage.getByRole('link', { name: 'Abrir APS Conecta Gestión ↗' })).toHaveAttribute('href', 'https://example.com');

  // Extract initial nextcloud password
  await expect(containersPage.getByRole('main')).toContainText('Contraseña inicial de APS Conecta Gestión:')
  const initialNextcloudPassword = await containersPage.locator('#initial-nextcloud-password').innerText();

  // Set backup location and create backup
  const borgBackupLocation = `/tmp/test/aio-${Math.floor(Math.random() * 2147483647)}`
  await containersPage.locator('#borg_backup_host_location').click();
  await containersPage.locator('#borg_backup_host_location').fill(borgBackupLocation);
  await containersPage.getByRole('button', { name: 'Enviar ubicación de la copia de seguridad' }).click();
  containersPage.once('dialog', dialog => {
    dialog.accept()
  });
  await containersPage.getByRole('button', { name: 'Crear copia de seguridad' }).click();
  await expect(containersPage.getByRole('main')).toContainText('El contenedor de copias de seguridad está actualmente en ejecución:', { timeout: 3 * 60 * 1000 });
  await expect(containersPage.getByRole('main')).toContainText('¡El último backup fue exitoso el', { timeout: 3 * 60 * 1000 });
  await containersPage.getByText('Haga clic aquí para mostrar todas las opciones de copia de seguridad').click();
  await expect(containersPage.locator('#borg-backup-password')).toBeVisible();
  const borgBackupPassword = await containersPage.locator('#borg-backup-password').innerText();

  // Assert that all containers are stopped
  await expect(containersPage.getByRole('button', { name: 'Iniciar contenedores' })).toBeVisible();

  // Save passwords for restore backup test
  writeFileSync('test_data.json', JSON.stringify({
    initialNextcloudPassword,
    borgBackupLocation,
    borgBackupPassword,
  }))
});