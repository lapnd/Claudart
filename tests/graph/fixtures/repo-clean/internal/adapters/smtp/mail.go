package smtp

import "example.com/acme/internal/ports/notification"

var _ notification.Port = Mailer{}
type Mailer struct{}
