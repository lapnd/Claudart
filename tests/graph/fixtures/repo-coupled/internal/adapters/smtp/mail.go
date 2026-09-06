package smtp

import (
	"example.com/acme/internal/ports/notification"
	"example.com/acme/internal/adapters/postgres"
)

var _ notification.Port = Mailer{}
type Mailer struct{ db postgres.Repo }
