package smtp

import (
	"example.com/acme/internal/ports/notification"
	"example.com/acme/internal/adapters/nope"
)

var _ notification.Port = Mailer{}
type Mailer struct{ x nope.T }
