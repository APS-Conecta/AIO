import { test, expect } from '@playwright/test';
import { writeFileSync } from 'node:fs'
import { logInToContainersPage } from './helpers.js';

// The es-CL suite (patch 090): every assertion the 060 sweep re-skinned now asserts the
// translated bytes the wizard actually renders. Two assertions stay English ON PURPOSE —
// they assert PHP exception bodies (ConfigurationManager.php:619/:1037), and the fork's
// zero-PHP rule keeps the 68 unreachable-PHP strings English. Those two lines are the
// suite's living proof that the sweep never bled into php/src.

test('Initial setup', async ({ page: setupPage }) => {
  test.setTimeout(10 * 60 * 1000)

  const containersPage = await logInToContainersPage(setupPage);

  // Reject IP addresses (PHP-borne English: ConfigurationManager.php:619 — stays, zero-PHP)
  await containersPage.locator('#domain').click();
  await containersPage.locator('#domain').fill('1.1.1.1');
  await containersPage.getByRole('button', { name: 'Enviar dominio' }).click();
  await expect(containersPage.locator('body')).toContainText('Please enter a domain and not an IP-address!');

  // Accept example.com (requires disabled domain validation)
  await containersPage.locator('#domain').click();
  await containersPage.locator('#domain').fill('example.com');
  await containersPage.getByRole('button', { name: 'Enviar dominio' }).click();

  // Disable all additional containers
  await containersPage.locator('#talk').uncheck();
  await containersPage.getByRole('checkbox', { name: 'Whiteboard' }).uncheck();
  await containersPage.getByRole('checkbox', { name: 'Imaginary' }).uncheck();
  await containersPage.getByText('Desactivar suite de oficina').click();
  await containersPage.getByRole('button', { name: 'Guardar cambios' }).last().click();
  await expect(containersPage.locator('#talk')).not.toBeChecked()
  await expect(containersPage.getByRole('checkbox', { name: 'Whiteboard' })).not.toBeChecked()
  await expect(containersPage.getByRole('checkbox', { name: 'Imaginary' })).not.toBeChecked()
  await expect(containersPage.locator('#office-none')).toBeChecked()

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
  await expect(containersPage.getByRole('link', { name: 'Abrir su Nextcloud ↗' })).toBeVisible({ timeout: 3 * 60 * 1000 });
  await expect(containersPage.getByRole('link', { name: 'Abrir su Nextcloud ↗' })).toHaveAttribute('href', 'https://example.com');

  // Extract initial nextcloud password
  await expect(containersPage.getByRole('main')).toContainText('Contraseña inicial de Nextcloud:')
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