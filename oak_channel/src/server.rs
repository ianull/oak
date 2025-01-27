//
// Copyright 2022 The Project Oak Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

use crate::{message, Channel, InvocationChannel};
use alloc::boxed::Box;
use anyhow::Context;

/// Starts a blocking server that listens for requests on the provided channel
/// and responds to them using the provided [`oak_idl::Transport`].
pub fn start_blocking_server<T: oak_idl::Transport<Error = !>>(
    channel: Box<dyn Channel>,
    mut server: T,
) -> anyhow::Result<!> {
    let channel_handle = &mut ServerChannelHandle::new(channel);
    loop {
        let request_message = channel_handle
            .read_request()
            .context("couldn't receive message")?;
        let request_message_invocation_id = request_message.invocation_id;
        let response = server.invoke(request_message.body.as_ref()).into_ok();
        let response_message = message::ResponseMessage {
            invocation_id: request_message_invocation_id,
            body: response,
        };
        channel_handle.write_response(response_message)?
    }
}

struct ServerChannelHandle {
    inner: InvocationChannel,
}

impl ServerChannelHandle {
    pub fn new(socket: Box<dyn Channel>) -> Self {
        Self {
            inner: InvocationChannel::new(socket),
        }
    }
    pub fn read_request(&mut self) -> anyhow::Result<message::RequestMessage> {
        let message = self.inner.read_message()?;
        Ok(message)
    }
    pub fn write_response(&mut self, response: message::ResponseMessage) -> anyhow::Result<()> {
        self.inner.write_message(response)
    }
}
