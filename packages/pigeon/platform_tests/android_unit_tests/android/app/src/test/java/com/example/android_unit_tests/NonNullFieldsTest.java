// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package com.example.android_unit_tests;

import static org.junit.Assert.*;

import com.example.android_unit_tests.NonNullFields.NonNullFieldSearchRequest;
import java.lang.IllegalStateException;
import org.junit.Test;

public class NonNullFieldsTest {
  @Test
  public void builder() {
    NonNullFieldSearchRequest request =
        new NonNullFieldSearchRequest.Builder().setQuery("hello").build();
    assertEquals(request.getQuery(), "hello");
  }

  @Test(expected = IllegalStateException.class)
  public void builderThrowsIfNull() {
    NonNullFieldSearchRequest request = new NonNullFieldSearchRequest.Builder().build();
  }
}
